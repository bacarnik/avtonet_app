/// Extended Local Catalog for Avto.net Brands and Models.
abstract final class AvtonetCatalog {
  static const String labelAllMakes = 'Vse znamke';
  static const String labelAllModels = 'Vsi modeli';

  static const List<String> makes = [
    '',
    'Abarth',
    'Alfa Romeo',
    'Alpine',
    'Aston Martin',
    'Audi',
    'BMW',
    'BYD',
    'Cadillac',
    'Chevrolet',
    'Chrysler',
    'Citroën',
    'Cupra',
    'Dacia',
    'Daewoo',
    'Daihatsu',
    'Dodge',
    'DS Automobiles',
    'Ferrari',
    'Fiat',
    'Fisker',
    'Ford',
    'Genesis',
    'Honda',
    'Hummer',
    'Hyundai',
    'Infiniti',
    'Jaguar',
    'Jeep',
    'Kia',
    'Lada',
    'Lamborghini',
    'Lancia',
    'Land Rover',
    'Lexus',
    'Lotus',
    'Maserati',
    'Mazda',
    'McLaren',
    'Mercedes-Benz',
    'MG',
    'MINI',
    'Mitsubishi',
    'Nissan',
    'Opel',
    'Peugeot',
    'Polestar',
    'Porsche',
    'Renault',
    'Rolls-Royce',
    'Rover',
    'Saab',
    'SEAT',
    'Škoda',
    'Smart',
    'SsangYong',
    'Subaru',
    'Suzuki',
    'Tesla',
    'Toyota',
    'Volkswagen',
    'Volvo',
  ];

  static const Map<String, List<String>> modelsByMake = {
    'Abarth': ['500', '595', '695', '124 Spider', 'Punto'],
    'Alfa Romeo': [
      '33', '75', '145', '146', '147', '155', '156', '159', '164', '166', 
      '4C', '8C', 'Brera', 'GT', 'GTV', 'Giulia', 'Giulietta', 'MiTo', 
      'Spider', 'Stelvio', 'Tonale', 'Crosswagon', 'Junior',
    ],
    'Audi': [
      '80', '90', '100', '200', 'A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8',
      'Q2', 'Q3', 'Q4', 'Q5', 'Q6', 'Q7', 'Q8', 'E-Tron', 'e-tron GT', 'TT', 'R8', 
      'RS3', 'RS4', 'RS5', 'RS6', 'RS7', 'S1', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 
      'SQ5', 'SQ7', 'SQ8', 'Allroad',
    ],
    'BMW': [
      'Serija 1', 'Serija 2', 'Serija 3', 'Serija 4', 'Serija 5', 'Serija 6', 'Serija 7', 'Serija 8',
      'i3', 'i4', 'i5', 'i7', 'i8', 'iX', 'iX1', 'iX2', 'iX3',
      'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M8',
      'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7', 'XM', 'Z1', 'Z3', 'Z4', 'Z8',
    ],
    'Citroën': [
      'C1', 'C2', 'C3', 'C3 Aircross', 'C3 Picasso', 'C4', 'C4 Aircross', 'C4 Cactus', 
      'C4 Picasso', 'C4 Grand Picasso', 'C5', 'C5 Aircross', 'C5 X', 'C6', 'C8', 
      'Berlingo', 'Jumper', 'Jumpy', 'Nemo', 'Saxo', 'Xsara', 'Xantia', 'XM', 'DS3', 'DS4', 'DS5',
    ],
    'Cupra': ['Ateca', 'Born', 'Formentor', 'Leon', 'Tavascan', 'Terramar'],
    'Dacia': ['Logan', 'Sandero', 'Duster', 'Lodgy', 'Dokker', 'Jogger', 'Spring'],
    'Fiat': [
      '500', '500C', '500L', '500X', '600', 'Panda', 'Punto', 'Punto Evo', 'Grande Punto',
      'Tipo', 'Bravo', 'Brava', 'Stilo', 'Croma', 'Doblo', 'Ducato', 'Scudo', 'Fiorino', 
      'Qubo', 'Sedici', 'Freemont', '124 Spider',
    ],
    'Ford': [
      'Ka', 'Fiesta', 'Fusion', 'Focus', 'C-Max', 'Mondeo', 'Mustang', 'Mustang Mach-E',
      'Puma', 'Kuga', 'EcoSport', 'Edge', 'Explorer', 'Galaxy', 'S-Max', 'B-Max', 
      'Tourneo', 'Transit', 'Ranger', 'Maverick', 'Escort', 'Sierra', 'Scorpio',
    ],
    'Hyundai': [
      'Atos', 'Getz', 'i10', 'i20', 'i30', 'i40', 'Accent', 'Elantra', 'Coupe',
      'ix20', 'ix35', 'ix55', 'Tucson', 'Santa Fe', 'Kona', 'Bayon', 'Staria',
      'Ioniq', 'Ioniq 5', 'Ioniq 6', 'Terracan', 'H-1',
    ],
    'Kia': [
      'Picanto', 'Rio', 'Ceed', 'Proceed', 'Optima', 'Stinger', 'Stonic', 'Soul', 
      'Niro', 'Sportage', 'Sorento', 'Carens', 'Carnival', 'EV6', 'EV9', 'XCeed', 'Venga',
    ],
    'Mazda': [
      '2', '3', '5', '6', '323', '626', 'CX-3', 'CX-30', 'CX-5', 'CX-60', 'CX-7', 
      'CX-8', 'CX-9', 'MX-3', 'MX-5', 'MX-30', 'RX-7', 'RX-8', 'Premacy', 'MPV', 'BT-50',
    ],
    'Mercedes-Benz': [
      'Razred A', 'Razred B', 'Razred C', 'Razred E', 'Razred S', 'Razred G', 'Razred V', 
      'Razred X', 'CLA', 'CLC', 'CLE', 'CLK', 'CLS', 'GLA', 'GLB', 'GLC', 'GLE', 'GLK', 
      'GLS', 'ML', 'SL', 'SLC', 'SLK', 'SLR', 'SLS', 'AMG GT', 'EQA', 'EQB', 'EQC', 
      'EQE', 'EQS', 'EQV', 'EQT', 'Sprinter', 'Vito', 'Citan', '190', '200', '220', '250', '300', '500',
    ],
    'Nissan': [
      'Micra', 'Note', 'Almera', 'Primera', 'Pulsar', 'Juke', 'Qashqai', 'X-Trail',
      'Pathfinder', 'Patrol', 'Murano', 'Leaf', 'Ariya', 'Navara', '350Z', '370Z', 'GT-R',
    ],
    'Opel': [
      'Adam', 'Agila', 'Ampera', 'Antara', 'Astra', 'Calibra', 'Cascada', 'Combo',
      'Corsa', 'Crossland', 'Frontera', 'Grandland', 'GT', 'Insignia', 'Meriva', 
      'Mokka', 'Omega', 'Signum', 'Speedster', 'Tigra', 'Vectra', 'Vivaro', 'Zafira', 'Movano',
    ],
    'Peugeot': [
      '106', '107', '108', '206', '207', '208', '301', '307', '308', '407', '408', 
      '508', '607', '807', '1007', '2008', '3008', '4007', '4008', '5008', 'Partner', 
      'Rifter', 'Traveller', 'Boxer', 'Bipper', 'RCZ', 'iOn',
    ],
    'Porsche': [
      '911', '924', '928', '944', 'Boxster', 'Cayman', '718', 'Cayenne', 'Macan', 'Panamera', 'Taycan',
    ],
    'Renault': [
      'Twingo', 'Clio', 'Megane', 'Scenic', 'Grand Scenic', 'Espace', 'Laguna',
      'Talisman', 'Captur', 'Kadjar', 'Austral', 'Arkana', 'Koleos', 'Fluence', 
      'Wind', 'Zoe', 'Kangoo', 'Trafic', 'Master', 'Rafale', 'Symbioz', 'R4', 'R5', 'R19',
    ],
    'SEAT': [
      'Mii', 'Ibiza', 'Cordoba', 'Leon', 'Toledo', 'Altea', 'Exeo', 'Arona', 'Ateca', 'Tarraco', 'Alhambra',
    ],
    'Škoda': [
      'Favorit', 'Felicia', 'Fabia', 'Roomster', 'Rapid', 'Scala', 'Octavia',
      'Superb', 'Yeti', 'Kamiq', 'Karoq', 'Kodiaq', 'Enyaq', 'Citigo', 'Elroq',
    ],
    'Tesla': ['Model 3', 'Model Y', 'Model S', 'Model X', 'Roadster', 'Cybertruck'],
    'Toyota': [
      'Aygo', 'Aygo X', 'Yaris', 'Yaris Cross', 'Corolla', 'Auris', 'Avensis', 
      'Verso', 'C-HR', 'RAV4', 'Highlander', 'Land Cruiser', 'Hilux', 'Prius', 
      'bZ4X', 'Camry', 'Supra', 'MR2', 'Celica', 'GT86', 'GR86',
    ],
    'Volkswagen': [
      'Up!', 'Fox', 'Lupo', 'Polo', 'Golf', 'Golf Plus', 'Golf Sportsvan', 'Jetta',
      'Bora', 'Passat', 'Passat CC', 'Arteon', 'CC', 'Scirocco', 'Beetle', 'Eos', 
      'Phaeton', 'Touran', 'Sharan', 'Caddy', 'Transporter', 'Multivan', 'California', 
      'T-Cross', 'Taigo', 'T-Roc', 'Tiguan', 'Touareg', 'Amarok', 'ID.3', 'ID.4', 
      'ID.5', 'ID.7', 'ID.Buzz', 'e-up!',
    ],
    'Volvo': [
      'C30', 'C40', 'S40', 'S60', 'S80', 'S90', 'V40', 'V50', 'V60', 'V70', 'V90', 
      'XC40', 'XC60', 'XC70', 'XC90', 'EX30', 'EX90',
    ],
  };

  static List<String> modelsForMake(String make) {
    if (make.isEmpty) return const [];
    return List<String>.from(modelsByMake[make] ?? const []);
  }

  static bool isKnownMake(String make) => make.isEmpty || modelsByMake.containsKey(make);
}
