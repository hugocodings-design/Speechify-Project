/// Voix Chirp3-HD de Google — la gamme la plus récente et la plus naturelle
/// de Cloud Text-to-Speech. Contrairement à Neural2, ce sont les 30 MÊMES
/// personas partagées telles quelles à travers toutes les langues (un même
/// "Kore" ou "Puck" parle aussi bien anglais que français) — donc une seule
/// table de personas, combinée avec la liste des langues où Google les offre.
///
/// Limitation confirmée par un test direct de l'API (voir conversation) :
/// Chirp3-HD accepte le SSML avec <mark> sans erreur, mais ne renvoie jamais
/// de "timepoints" — donc pas de surlignage mot par mot possible pour ces
/// voix, seulement un surlignage de la phrase entière.
class Chirp3Persona {
  final String name;
  final bool isFemale;

  const Chirp3Persona(this.name, this.isFemale);
}

const List<Chirp3Persona> chirp3Personas = [
  Chirp3Persona('Achernar', true),
  Chirp3Persona('Achird', false),
  Chirp3Persona('Algenib', false),
  Chirp3Persona('Algieba', false),
  Chirp3Persona('Alnilam', false),
  Chirp3Persona('Aoede', true),
  Chirp3Persona('Autonoe', true),
  Chirp3Persona('Callirrhoe', true),
  Chirp3Persona('Charon', false),
  Chirp3Persona('Despina', true),
  Chirp3Persona('Enceladus', false),
  Chirp3Persona('Erinome', true),
  Chirp3Persona('Fenrir', false),
  Chirp3Persona('Gacrux', true),
  Chirp3Persona('Iapetus', false),
  Chirp3Persona('Kore', true),
  Chirp3Persona('Laomedeia', true),
  Chirp3Persona('Leda', true),
  Chirp3Persona('Orus', false),
  Chirp3Persona('Puck', false),
  Chirp3Persona('Pulcherrima', true),
  Chirp3Persona('Rasalgethi', false),
  Chirp3Persona('Sadachbia', false),
  Chirp3Persona('Sadaltager', false),
  Chirp3Persona('Schedar', false),
  Chirp3Persona('Sulafat', true),
  Chirp3Persona('Umbriel', false),
  Chirp3Persona('Vindemiatrix', true),
  Chirp3Persona('Zephyr', true),
  Chirp3Persona('Zubenelgenubi', false),
];

/// Langues où Chirp3-HD est disponible (vérifié via list_voices — pt-PT n'en
/// a aucune, contrairement aux autres langues déjà présentes dans l'app).
const Map<String, String> chirp3Languages = {
  'en-US': 'Anglais (US)',
  'en-GB': 'Anglais (UK)',
  'fr-CA': 'Français (Canada)',
  'fr-FR': 'Français (France)',
  'es-ES': 'Espagnol (Espagne)',
  'es-US': 'Espagnol (US)',
  'pt-BR': 'Portugais (Brésil)',
};

/// Prénoms courants, familiers à la population de chaque langue —
/// remplacent les noms astronomiques d'origine (Achernar, Zubenelgenubi...)
/// qui ne parlent à personne. Chaque liste suit EXACTEMENT le même ordre
/// (et donc le même genre à chaque position) que [chirp3Personas], pour un
/// mappage direct par index. Choisis pour ne pas faire doublon avec les
/// prénoms déjà utilisés par les voix Neural2 de la même langue.
const Map<String, List<String>> chirp3LocalizedNames = {
  'en-US': [
    'Olivia', 'James', 'William', 'Ethan', 'Daniel', 'Sophia', 'Charlotte',
    'Amelia', 'Benjamin', 'Harper', 'Samuel', 'Evelyn', 'Nathan', 'Abigail',
    'Ryan', 'Emily', 'Elizabeth', 'Grace', 'Andrew', 'Joshua', 'Mia',
    'Christopher', 'Jacob', 'Tyler', 'Matthew', 'Victoria', 'Alexander',
    'Natalie', 'Chloe', 'Brandon',
  ],
  'en-GB': [
    'Freya', 'George', 'Thomas', 'Harry', 'Jack', 'Isla', 'Poppy', 'Alice',
    'Charlie', 'Ruby', 'Leo', 'Millie', 'Archie', 'Florence', 'Henry',
    'Daisy', 'Rosie', 'Phoebe', 'Edward', 'Jacob', 'Ella', 'Alfie', 'Theo',
    'Freddie', 'Arthur', 'Matilda', 'Louis', 'Amelia', 'Grace', 'Oscar',
  ],
  'fr-CA': [
    'Léa', 'Félix', 'Xavier', 'Olivier', 'Nicolas', 'Rosalie', 'Charlotte',
    'Alicia', 'Maxime', 'Juliette', 'Simon', 'Emma', 'Thomas', 'Sarah',
    'Alexandre', 'Coralie', 'Mélodie', 'Ophélie', 'Vincent', 'Mathis', 'Zoé',
    'Julien', 'Loïc', 'Raphaël', 'Benoît', 'Florence', 'Jérôme', 'Amélie',
    'Laurence', 'Mathieu',
  ],
  'fr-FR': [
    'Camille', 'Julien', 'Maxime', 'Nicolas', 'Alexandre', 'Manon', 'Léa',
    'Charlotte', 'Thibault', 'Juliette', 'Louis', 'Emma', 'Hugo', 'Sarah',
    'Victor', 'Zoé', 'Margaux', 'Ophélie', 'Romain', 'Baptiste', 'Inès',
    'Mathieu', 'Loïc', 'Raphaël', 'Benoît', 'Amandine', 'Clément', 'Élise',
    'Pauline', 'Théo',
  ],
  'es-ES': [
    'Lucía', 'Pablo', 'Álvaro', 'Adrián', 'Hugo', 'Martina', 'Paula',
    'Carla', 'Javier', 'Elena', 'Marcos', 'Claudia', 'Sergio', 'Alba',
    'Iván', 'Sara', 'Irene', 'Nerea', 'Rubén', 'Óscar', 'Aitana', 'Enrique',
    'Nacho', 'Bruno', 'Raúl', 'Marta', 'Gonzalo', 'Cristina', 'Lola',
    'Fernando',
  ],
  'es-US': [
    'Ximena', 'Mateo', 'Diego', 'Emiliano', 'Alejandro', 'Valeria', 'Renata',
    'Daniela', 'Andrés', 'Fernanda', 'Joaquín', 'Regina', 'Leonardo',
    'Ariana', 'Gael', 'Julieta', 'Amanda', 'Victoria', 'Ricardo', 'Esteban',
    'Antonella', 'Rodrigo', 'Iker', 'Tomás', 'Cristian', 'Paola', 'Marco',
    'Lucero', 'Selena', 'Damián',
  ],
  'pt-BR': [
    'Camila', 'Lucas', 'Gabriel', 'Matheus', 'Felipe', 'Bianca', 'Juliana',
    'Fernanda', 'Bruno', 'Amanda', 'André', 'Carolina', 'Diego', 'Isabela',
    'Thiago', 'Vitória', 'Gabriela', 'Natália', 'Eduardo', 'Vinícius',
    'Letícia', 'Fábio', 'Marcelo', 'Ricardo', 'Otávio', 'Renata', 'Leonardo',
    'Priscila', 'Marina', 'Gustavo',
  ],
};
