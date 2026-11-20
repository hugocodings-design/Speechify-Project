#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <ctime>
#include <cstring>
#include <algorithm>
#include <time.h>
#include <android/log.h>
#include "llama.cpp/include/llama.h"
#include <vulkan/vulkan.h>


#define LOG_TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::atomic<bool> g_stop_flag{false};
static int g_n_past = 0;  // Track the number of tokens already in KV cache

// Helper function to validate UTF-8 strings
static bool isValidUTF8(const char* str, size_t len) {
    if (!str) return false;
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            i++;
            continue;
        }
        
        // Multi-byte sequence start (110xxxxx, 1110xxxx, or 11110xxx)
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2; // 110xxxxx
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3; // 1110xxxx
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4; // 11110xxx
        } else {
            // Invalid first byte
            return false;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            return false;
        }
        
        // Check continuation bytes (10xxxxxx)
        for (int j = 1; j < num_bytes; j++) {
            if ((bytes[i + j] & 0xC0) != 0x80) {
                return false;
            }
        }
        
        // Check for overlong encodings and invalid code points
        if (num_bytes == 2) {
            // Overlong encoding of ASCII character
            if ((c & 0x1E) == 0) return false;
        } else if (num_bytes == 3) {
            // Invalid surrogate halves (U+D800-U+DFFF)
            if (c == 0xED && (bytes[i + 1] & 0x20) == 0x20) return false;
            // Overlong encoding
            if (c == 0xE0 && (bytes[i + 1] & 0x20) == 0) return false;
        } else if (num_bytes == 4) {
            // Out of Unicode range (> U+10FFFF)
            if (c > 0xF4) return false;
            // Overlong encoding
            if (c == 0xF0 && (bytes[i + 1] & 0x30) == 0) return false;
            // Invalid code points (> U+10FFFF)
            if (c == 0xF4 && bytes[i + 1] > 0x8F) return false;
        }
        
        i += num_bytes;
    }
    
    return true;
}

// Helper function to sanitize UTF-8 strings
static std::string sanitizeUTF8(const char* str, size_t len) {
    if (!str || len == 0) return "";
    
    // First try to validate as-is
    if (isValidUTF8(str, len)) {
        return std::string(str, len);
    }
    
    // If invalid, create a sanitized version
    std::string result;
    result.reserve(len);
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            result += c;
            i++;
            continue;
        }
        
        // Multi-byte sequence start
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2;
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3;
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4;
        } else {
            // Invalid first byte, replace with replacement character
            result += "\xEF\xBF\xBD"; // 
            i++;
            continue;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            result += "\xEF\xBF\xBD"; // 
            break;
        }
        
        // Extract the sequence
        std::string seq(reinterpret_cast<const char*>(bytes + i), num_bytes);
        
        // Validate the sequence
        if (isValidUTF8(seq.c_str(), num_bytes)) {
            result += seq;
        } else {
            // Invalid sequence, replace with replacement character
            result += "\xEF\xBF\xBD"; // 
        }
        
        i += num_bytes;
    }
    
    return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeDetectGpu(
        JNIEnv* env, jobject /* this */, jlongArray outStats) {

    // Zero out output array as safe default (-1 = unknown)
    jlong defaults[2] = {-1L, -1L};
    env->SetLongArrayRegion(outStats, 0, 2, defaults);

    // Minimal instance — no extensions, no validation layers (crash risk on some devices)
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = 0;
    createInfo.ppEnabledExtensionNames = nullptr;
    createInfo.enabledLayerCount = 0;
    createInfo.ppEnabledLayerNames = nullptr;

    VkInstance instance = VK_NULL_HANDLE;
    if (vkCreateInstance(&createInfo, nullptr, &instance) != VK_SUCCESS) {
        LOGI("nativeDetectGpu: vkCreateInstance failed — no Vulkan");
        return nullptr;
    }

    // Enumerate physical devices
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        LOGI("nativeDetectGpu: no physical devices found");
        vkDestroyInstance(instance, nullptr);
        return nullptr;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());

    // Select device with the largest device-local memory heap
    VkPhysicalDevice bestDevice = VK_NULL_HANDLE;
    VkDeviceSize bestHeapSize = 0;

    for (auto& dev : devices) {
        VkPhysicalDeviceMemoryProperties memProps{};
        vkGetPhysicalDeviceMemoryProperties(dev, &memProps);
        for (uint32_t i = 0; i < memProps.memoryHeapCount; i++) {
            if ((memProps.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) &&
                memProps.memoryHeaps[i].size > bestHeapSize) {
                bestHeapSize = memProps.memoryHeaps[i].size;
                bestDevice = dev;
            }
        }
    }

    if (bestDevice == VK_NULL_HANDLE) {
        LOGI("nativeDetectGpu: no device-local memory found");
        vkDestroyInstance(instance, nullptr);
        return nullptr;
    }

    // Check for compute queue support
    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(bestDevice, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(bestDevice, &queueFamilyCount, queueFamilies.data());

    bool hasComputeQueue = false;
    for (auto& qf : queueFamilies) {
        if (qf.queueFlags & VK_QUEUE_COMPUTE_BIT) {
            hasComputeQueue = true;
            break;
        }
    }

    if (!hasComputeQueue) {
        LOGI("nativeDetectGpu: no compute queue — GPU not usable for inference");
        vkDestroyInstance(instance, nullptr);
        return nullptr;
    }

    // Read device properties
    VkPhysicalDeviceProperties props{};
    vkGetPhysicalDeviceProperties(bestDevice, &props);

    // Populate outStats
    jlong stats[2];
    stats[0] = static_cast<jlong>(props.apiVersion);
    stats[1] = static_cast<jlong>(bestHeapSize);
    env->SetLongArrayRegion(outStats, 0, 2, stats);

    LOGI("nativeDetectGpu: GPU='%s' apiVersion=%u heapSize=%llu hasCompute=%d",
         props.deviceName,
         props.apiVersion,
         (unsigned long long)bestHeapSize,
         hasComputeQueue ? 1 : 0);

    vkDestroyInstance(instance, nullptr);
    return env->NewStringUTF(props.deviceName);
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring path, jlong n_threads, jlong ctx_size, jlong n_gpu_layers,
    jobject progress_callback) {
    
    const char* model_path = env->GetStringUTFChars(path, nullptr);
    LOGI("Loading model: %s", model_path);

    // Model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers;
    // TalkTome : pas de mmap. Sous Android, les pages d'un fichier mappé
    // sont « récupérables » : le système les jette dès qu'il veut de la
    // mémoire, et chaque mot généré relisait alors des morceaux du modèle
    // sur le stockage (mesuré : ~2 jetons/s). Chargé en RAM, il y reste.
    model_params.use_mmap = false;
    
    // Load model
    g_model = llama_model_load_from_file(model_path, model_params);
    env->ReleaseStringUTFChars(path, model_path);
    
    if (!g_model) {
        LOGE("Failed to load model");
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to load model");
        return;
    }

    // Context parameters with memory optimizations for low-end devices
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    
    // Memory optimization: reduce memory usage by limiting batch processing
    ctx_params.n_batch = 512;  // Process smaller batches to reduce memory spikes

    // Create context (using new API)
    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (!g_ctx) {
        llama_model_free(g_model);
        g_model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to create context");
        return;
    }

    // Get vocab for tokenization
    g_vocab = llama_model_get_vocab(g_model);
    LOGI("Vocab initialized: %p", (void*)g_vocab);
    
    if (!g_vocab) {
        llama_free(g_ctx);
        llama_model_free(g_model);
        g_ctx = nullptr;
        g_model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to get vocab from model");
        return;
    }
    
    // Reset KV cache position counter for new model
    g_n_past = 0;

    // Report progress completion
    if (progress_callback) {
        jclass callbackClass = env->GetObjectClass(progress_callback);
        jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");
        
        // Create Double object for 1.0
        jclass doubleClass = env->FindClass("java/lang/Double");
        jmethodID doubleConstructor = env->GetMethodID(doubleClass, "<init>", "(D)V");
        jobject doubleObj = env->NewObject(doubleClass, doubleConstructor, 1.0);
        
        env->CallObjectMethod(progress_callback, invokeMethod, doubleObj);
        env->DeleteLocalRef(doubleObj);
        env->DeleteLocalRef(callbackClass);
    }

    LOGI("Model loaded successfully");
}

static jobject g_token_callback = nullptr;

// TalkTome : jetons du prompt + de la réponse actuellement présents dans le
// cache KV. Le prompt suivant ne recalcule que ce qui diffère (le long
// préambule d'instructions, identique d'une requête à l'autre, est gratuit
// après la première fois).
static std::vector<llama_token> g_cached_tokens;

// Longueur du plus long préfixe UTF-8 complet de s (les octets d'un
// caractère accentué peuvent arriver sur deux jetons successifs).
static size_t completeUtf8Prefix(const std::string& s) {
    size_t i = 0, ok = 0;
    const size_t n = s.size();
    while (i < n) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        size_t len = (c & 0x80) == 0 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : (c & 0xF8) == 0xF0 ? 4 : 1;
        if (i + len > n) break;
        i += len;
        ok = i;
    }
    return ok;
}

static int64_t nowMs() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGenerate(
    JNIEnv* env, jobject thiz,
    jstring prompt, jlong max_tokens,
    jdouble temperature, jdouble top_p, jlong top_k, jdouble min_p, jdouble typical_p,
    jdouble repeat_penalty, jdouble frequency_penalty, jdouble presence_penalty, jlong repeat_last_n,
    jlong mirostat, jdouble mirostat_tau, jdouble mirostat_eta,
    jlong seed, jboolean penalize_newline,
    jobject token_callback) {

    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }

    if (!g_model || !g_ctx || !g_vocab) {
        jclass exception = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(exception, "Model not loaded");
        return;
    }
    g_token_callback = env->NewGlobalRef(token_callback);
    g_stop_flag = false;
    const int64_t t0 = nowMs();

    // ── Tokenisation ────────────────────────────────────────────────────────
    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    std::string prompt_s = sanitizeUTF8(prompt_str, strlen(prompt_str));
    env->ReleaseStringUTFChars(prompt, prompt_str);

    const int n_needed = -llama_tokenize(g_vocab, prompt_s.c_str(), prompt_s.size(), nullptr, 0, true, true);
    if (n_needed <= 0) {
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to tokenize prompt");
        return;
    }
    std::vector<llama_token> tokens(n_needed);
    const int n_tok = llama_tokenize(g_vocab, prompt_s.c_str(), prompt_s.size(), tokens.data(), tokens.size(), true, true);
    if (n_tok < 0) {
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to tokenize prompt");
        return;
    }
    tokens.resize(n_tok);

    const int n_ctx = llama_n_ctx(g_ctx);
    if ((int)tokens.size() + (int)max_tokens > n_ctx) {
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Prompt too long for context");
        return;
    }

    // ── Réutilisation du préfixe déjà en cache ──────────────────────────────
    size_t n_common = 0;
    while (n_common < g_cached_tokens.size() && n_common < tokens.size() &&
           g_cached_tokens[n_common] == tokens[n_common]) {
        n_common++;
    }
    // Il faut décoder au moins un jeton pour obtenir des logits.
    if (n_common == tokens.size()) n_common--;
    llama_memory_t mem = llama_get_memory(g_ctx);
    if (!llama_memory_seq_rm(mem, 0, (llama_pos)n_common, -1)) {
        llama_memory_seq_rm(mem, 0, 0, -1);
        n_common = 0;
    }
    g_cached_tokens.resize(n_common);

    // ── Prompt (seulement la partie nouvelle) ───────────────────────────────
    const int max_batch_size = 512;
    llama_batch batch = llama_batch_init(max_batch_size, 0, 1);
    size_t pos = n_common;
    while (pos < tokens.size()) {
        const int bs = std::min((int)(tokens.size() - pos), max_batch_size);
        for (int i = 0; i < bs; i++) {
            batch.token[i] = tokens[pos + i];
            batch.pos[i] = (llama_pos)(pos + i);
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = 0;
            batch.logits[i] = (pos + i == tokens.size() - 1);
        }
        batch.n_tokens = bs;
        if (llama_decode(g_ctx, batch) != 0) {
            LOGE("Failed to decode prompt");
            llama_batch_free(batch);
            llama_memory_seq_rm(mem, 0, 0, -1);
            g_cached_tokens.clear();
            g_n_past = 0;
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to decode prompt");
            return;
        }
        g_cached_tokens.insert(g_cached_tokens.end(), tokens.begin() + pos, tokens.begin() + pos + bs);
        pos += bs;
    }
    g_n_past = (int)g_cached_tokens.size();
    const int64_t t1 = nowMs();

    // ── Échantillonneur ─────────────────────────────────────────────────────
    if (g_sampler) llama_sampler_free(g_sampler);
    uint32_t sampler_seed = (seed >= 0) ? static_cast<uint32_t>(seed) : static_cast<uint32_t>(time(nullptr));
    g_sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (repeat_penalty != 1.0f || frequency_penalty != 0.0f || presence_penalty != 0.0f) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(
            repeat_last_n, repeat_penalty, frequency_penalty, presence_penalty));
    }
    if (temperature <= 0.0) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_greedy());
    } else {
        if (top_k > 0) llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
        if (top_p < 1.0f) llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
        if (min_p > 0.0f && min_p < 1.0f) llama_sampler_chain_add(g_sampler, llama_sampler_init_min_p(min_p, 1));
        llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(sampler_seed));
    }

    jclass callbackClass = env->GetObjectClass(token_callback);
    jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");

    // ── Génération ──────────────────────────────────────────────────────────
    std::string pending;
    int n_gen = 0;
    for (int i = 0; i < max_tokens && !g_stop_flag; i++) {
        llama_token tok = llama_sampler_sample(g_sampler, g_ctx, -1);
        if (llama_vocab_is_eog(g_vocab, tok)) break;

        char buffer[256];
        int32_t length = llama_token_to_piece(g_vocab, tok, buffer, sizeof(buffer), 0, false);
        if (length > 0) pending.append(buffer, length);
        const size_t ok = completeUtf8Prefix(pending);
        if (ok > 0) {
            std::string out = sanitizeUTF8(pending.data(), ok);
            pending.erase(0, ok);
            jstring token_str = env->NewStringUTF(out.c_str());
            env->CallObjectMethod(g_token_callback, invokeMethod, token_str);
            env->DeleteLocalRef(token_str);
        }

        batch.n_tokens = 1;
        batch.token[0] = tok;
        batch.pos[0] = (llama_pos)g_cached_tokens.size();
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = true;
        if (llama_decode(g_ctx, batch) != 0) {
            LOGE("Failed to decode generated token");
            break;
        }
        g_cached_tokens.push_back(tok);
        n_gen++;
    }
    g_n_past = (int)g_cached_tokens.size();
    const int64_t t2 = nowMs();
    LOGI("[PERF] prompt %d tok (%d reused) in %lld ms | %d tok generated in %lld ms (%.1f tok/s)",
         (int)tokens.size(), (int)n_common, (long long)(t1 - t0), n_gen, (long long)(t2 - t1),
         n_gen > 0 ? n_gen * 1000.0 / (double)std::max<int64_t>(1, t2 - t1) : 0.0);

    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }
    llama_batch_free(batch);
    env->DeleteLocalRef(callbackClass);
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeStop(
    JNIEnv* env, jobject thiz) {
    g_stop_flag = true;
    // When stopping generation, we just set the flag - KV cache management handled by llama.cpp
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeFreeModel(
    JNIEnv* env, jobject thiz) {
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_vocab = nullptr;
    g_n_past = 0;  // Reset position counter
    g_cached_tokens.clear();
    
    LOGI("Model freed");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetTokensUsed(
    JNIEnv* env, jobject thiz) {
    return g_n_past;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetContextSize(
    JNIEnv* env, jobject thiz) {
    return g_ctx ? llama_n_ctx(g_ctx) : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeClearContext(
    JNIEnv* env, jobject thiz) {
    if (!g_ctx) {
        LOGE("Cannot clear context: context is null");
        return;
    }
    
    llama_memory_t mem = llama_get_memory(g_ctx);
    if (mem) {
        llama_memory_seq_rm(mem, 0, 0, -1);
        g_n_past = 0;
        g_cached_tokens.clear();
        LOGI("Context cleared, g_n_past reset to 0");
    } else {
        LOGE("Failed to get memory object from context");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSetSystemPromptLength(
    JNIEnv* env, jobject thiz, jint length) {
    // Currently not used but available for future smart context management
    LOGI("System prompt length set to: %d tokens (currently unused)", length);
}