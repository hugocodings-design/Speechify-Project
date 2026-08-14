import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ebook.dart';
import '../services/file_service.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Box<Ebook> ebookBox;
  final fileService = FileService();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    ebookBox = await Hive.openBox<Ebook>('ebooks');
    setState(() {});
  }

  Future<void> _pickAndUploadFile() async {
    try {
      setState(() => isLoading = true);

      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub'],
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          // Extract text from file
          final chapters = await fileService.extractText(filePath);

          // Create ebook object
          final fileFormat = fileService.detectFileFormat(filePath);
          final ebook = Ebook(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: result.files.first.name,
            chapters: chapters,
            uploadedAt: DateTime.now(),
            fileFormat: fileFormat,
          );

          // Save to Hive
          await ebookBox.put(ebook.id, ebook);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${ebook.title} uploaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          setState(() {});
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _openEbook(Ebook ebook) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(ebook: ebook),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speechify'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Paramètres',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ebookBox.isEmpty
          ? _buildEmptyState()
          : _buildEbookList(),
      floatingActionButton: FloatingActionButton(
        onPressed: isLoading ? null : _pickAndUploadFile,
        tooltip: 'Upload Ebook',
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Ebooks Yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Upload a PDF or EPUB to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEbookList() {
    final ebooks = ebookBox.values.toList();
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: ebooks.length,
      itemBuilder: (context, index) {
        final ebook = ebooks[index];
        
        return Card(
          child: ListTile(
            leading: Icon(
              ebook.fileFormat == 'pdf'
                  ? Icons.picture_as_pdf
                  : Icons.import_contacts,
              color: Colors.blue,
            ),
            title: Text(ebook.title),
            subtitle: Text(
              '${ebook.chapters.length} chapitres • ${ebook.totalWords} mots',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_filled, color: Colors.blue[400]),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Supprimer'),
                        content: Text('Supprimer "${ebook.title}" ?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Supprimer',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ebookBox.delete(ebook.id);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            onTap: () => _openEbook(ebook),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    ebookBox.close();
    super.dispose();
  }
}
