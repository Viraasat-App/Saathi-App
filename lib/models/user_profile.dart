class UserProfile {
  final String userId;
  final String phoneNumber;
  final String name;
  final int age;
  final String gender;
  final String language;
  final String city;
  final String occupation;
  final String hobbies;

  const UserProfile({
    required this.userId,
    required this.phoneNumber,
    required this.name,
    required this.age,
    required this.gender,
    required this.language,
    required this.city,
    required this.occupation,
    required this.hobbies,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'phoneNumber': phoneNumber,
    'name': name,
    'age': age,
    'gender': gender,
    'language': language,
    'city': city,
    'occupation': occupation,
    'hobbies': hobbies,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: (json['userId'] ?? '') as String,
      phoneNumber: (json['phoneNumber'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      age: (json['age'] ?? 0) as int,
      gender: (json['gender'] ?? '') as String,
      language: (json['language'] ?? '') as String,
      city: (json['city'] ?? '') as String,
      occupation: (json['occupation'] ?? '') as String,
      hobbies: (json['hobbies'] ?? '') as String,
    );
  }
}
