import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/auth_storage.dart';
import '../services/chat_history_storage.dart';
import '../services/chat_session_snapshot.dart';
import '../services/profile_storage.dart';
import '../services/profile_sync_service.dart';
import '../theme/saathi_beige_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _hobbiesController = TextEditingController();

  String? _gender;
  String? _language;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = true;
  String? _userId;
  String? _phoneNumber;

  void _showSystemPopup(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Colors.black87),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: SaathiBeige.accentDeep.withValues(alpha: 0.45),
            ),
          ),
          elevation: 8,
          duration: const Duration(seconds: 2),
          backgroundColor: SaathiBeige.surfaceElevated.withValues(alpha: 0.96),
        ),
      );
  }

  Future<void> _logout() async {
    await ChatHistoryStorage.instance.clearAllLocalChatData();
    ChatSessionSnapshot.clear();
    await AuthService.instance.signOut();
    await AuthStorage.instance.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _confirmLogout() async {
    final scheme = Theme.of(context).colorScheme;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SaathiBeige.surfaceElevated,
          surfaceTintColor: SaathiBeige.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: SaathiBeige.accent.withValues(alpha: 0.35),
            ),
          ),
          title: const Text('Logout?'),
          content: const Text('Do you want to logout from this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    if (shouldLogout != true) return;
    await _logout();
  }

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final profile = await ProfileStorage.instance.loadUserProfile();
    final userId = await AuthStorage.instance.currentUserId();
    final phoneNumber = await AuthStorage.instance.currentPhoneNumber();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _userId = userId;
      _phoneNumber = phoneNumber;
      _phoneController.text = phoneNumber ?? '';
      if (profile != null) {
        _nameController.text = profile.name;
        _ageController.text = profile.age.toString();
        _gender = profile.gender;
        _language = profile.language;
        _cityController.text = profile.city;
        _occupationController.text = profile.occupation;
        _hobbiesController.text = profile.hobbies;
        _isEditing = false;
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _cityController.dispose();
    _occupationController.dispose();
    _hobbiesController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (!_isEditing) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    if (_gender == null || _language == null) return;

    final age = int.tryParse(_ageController.text.trim());
    if (age == null || age <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid age.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final session = await AuthStorage.instance.loadSession();
    final userId = session?.sub ?? _userId ?? '';
    final phoneNumber = session?.username ?? _phoneNumber ?? '';
    if (session == null || userId.isEmpty || phoneNumber.isEmpty) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login session missing. Please sign in again.'),
        ),
      );
      return;
    }

    final profile = UserProfile(
      userId: userId,
      phoneNumber: phoneNumber,
      name: _nameController.text.trim(),
      age: age,
      gender: _gender!,
      language: _language!,
      city: _cityController.text.trim(),
      occupation: _occupationController.text.trim(),
      hobbies: _hobbiesController.text.trim(),
    );

    await ProfileStorage.instance.saveUserProfile(profile);
    final syncResult = await ProfileSyncService.instance.syncProfile(
      session: session,
      profile: profile,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });
    switch (syncResult) {
      case ProfileSyncFailure(:final message):
        _showSystemPopup(message);
      case ProfileSyncSuccess():
        _showSystemPopup('Profile saved and synced');
    }
    Navigator.pushReplacementNamed(context, '/chat');
  }

  static const _inputRadius = 16.0;

  InputDecoration _modernDecoration({
    required ThemeData theme,
    required String label,
    IconData? icon,
    bool disabledLook = false,
  }) {
    final scheme = theme.colorScheme;
    final disabledFill = scheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_inputRadius),
      borderSide: BorderSide(
        color: SaathiBeige.accent.withValues(alpha: 0.2),
      ),
    );
    return InputDecoration(
      prefixIcon: icon != null
          ? Icon(icon, color: SaathiBeige.accentDeep.withValues(alpha: 0.88))
          : null,
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 14,
        color: SaathiBeige.muted,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: disabledLook
          ? disabledFill
          : SaathiBeige.surfaceElevated.withValues(alpha: 0.72),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_inputRadius),
        borderSide: BorderSide(color: SaathiBeige.accentDeep, width: 1.6),
      ),
      disabledBorder: border,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.35,
          fontWeight: FontWeight.w700,
          color: SaathiBeige.muted.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: SaathiBeige.surfaceElevated.withValues(alpha: 0.78),
        border: Border.all(color: SaathiBeige.accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: SaathiBeige.charcoal.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final genderItems = const ['Male', 'Female', 'Other'];
    final languageItems = const [
      'English',
      'Hindi',
      'Tamil',
      'Telugu',
      'Kannada',
      'Other',
    ];
    final disabledFill = scheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final displayName = _nameController.text.trim().isEmpty
        ? 'Your profile'
        : _nameController.text.trim();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: SaathiBeige.cream.withValues(alpha: 0.92),
        foregroundColor: SaathiBeige.charcoal,
        elevation: 0,
        title: const Text('Profile'),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(Icons.edit_outlined, color: SaathiBeige.accentDeep),
              label: Text(
                'Edit',
                style: TextStyle(
                  color: SaathiBeige.accentDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(
                    color: SaathiBeige.accent.withValues(alpha: 0.35),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                backgroundColor: SaathiBeige.surfaceElevated.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: SaathiBeige.backgroundGradient,
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        const SizedBox(height: 4),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      SaathiBeige.accent.withValues(alpha: 0.45),
                                      SaathiBeige.accentDeep.withValues(
                                        alpha: 0.88,
                                      ),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: SaathiBeige.accentDeep.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                displayName,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: SaathiBeige.charcoal,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _phoneController.text.isEmpty
                                    ? 'Signed in'
                                    : _phoneController.text,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: SaathiBeige.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Saathi ke saath behtar anubhav',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: SaathiBeige.muted.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionTitle('Account'),
                              _glassCard(
                                child: TextFormField(
                                  controller: _phoneController,
                                  enabled: false,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _modernDecoration(
                                    theme: theme,
                                    label: 'Mobile number',
                                    icon: Icons.phone_rounded,
                                    disabledLook: true,
                                  ).copyWith(fillColor: disabledFill),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _sectionTitle('About you'),
                              _glassCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                  TextFormField(
                                    controller: _nameController,
                                    enabled: _isEditing,
                                    textInputAction: TextInputAction.next,
                                    decoration: _modernDecoration(
                                      theme: theme,
                                      label: 'Name',
                                      icon: Icons.person_rounded,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Please enter your name.'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _ageController,
                                    enabled: _isEditing,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: _modernDecoration(
                                      theme: theme,
                                      label: 'Age',
                                      icon: Icons.cake_rounded,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    validator: (v) {
                                      final raw = v?.trim() ?? '';
                                      final n = int.tryParse(raw);
                                      if (n == null || n <= 0) {
                                        return 'Enter a valid age.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    initialValue: _gender,
                                    items: genderItems
                                        .map(
                                          (g) => DropdownMenuItem(
                                            value: g,
                                            child: Text(
                                              g,
                                              style: TextStyle(
                                                fontSize: 17,
                                                color: scheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    decoration: _modernDecoration(
                                      theme: theme,
                                      label: 'Gender',
                                      icon: Icons.people_alt_rounded,
                                      disabledLook: !_isEditing,
                                    ).copyWith(
                                      fillColor: _isEditing
                                          ? null
                                          : disabledFill,
                                    ),
                                    dropdownColor:
                                        scheme.surfaceContainerHighest,
                                    onChanged: _isEditing
                                        ? (v) => setState(() => _gender = v)
                                        : null,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: _isEditing
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                    ),
                                    iconEnabledColor: scheme.onSurface,
                                    iconDisabledColor: scheme.onSurfaceVariant,
                                    menuMaxHeight: 320,
                                    validator: (v) => v == null
                                        ? 'Please select gender.'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    initialValue: _language,
                                    items: languageItems
                                        .map(
                                          (l) => DropdownMenuItem(
                                            value: l,
                                            child: Text(
                                              l,
                                              style: TextStyle(
                                                fontSize: 17,
                                                color: scheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    decoration: _modernDecoration(
                                      theme: theme,
                                      label: 'Language',
                                      icon: Icons.language_rounded,
                                      disabledLook: !_isEditing,
                                    ).copyWith(
                                      fillColor: _isEditing
                                          ? null
                                          : disabledFill,
                                    ),
                                    dropdownColor:
                                        scheme.surfaceContainerHighest,
                                    onChanged: _isEditing
                                        ? (v) => setState(() => _language = v)
                                        : null,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: _isEditing
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                    ),
                                    iconEnabledColor: scheme.onSurface,
                                    iconDisabledColor: scheme.onSurfaceVariant,
                                    menuMaxHeight: 320,
                                    validator: (v) => v == null
                                        ? 'Please select language.'
                                        : null,
                                  ),
                                ],
                              ),
                              ),
                              const SizedBox(height: 20),
                              _sectionTitle('Location & work'),
                              _glassCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextFormField(
                                      controller: _cityController,
                                      enabled: _isEditing,
                                      textInputAction: TextInputAction.next,
                                      decoration: _modernDecoration(
                                        theme: theme,
                                        label: 'City',
                                        icon: Icons.location_city_rounded,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'Please enter your city.'
                                          : null,
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _occupationController,
                                      enabled: _isEditing,
                                      textInputAction: TextInputAction.next,
                                      decoration: _modernDecoration(
                                        theme: theme,
                                        label: 'Occupation',
                                        icon: Icons.work_rounded,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'Please enter your occupation.'
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              _sectionTitle('Interests'),
                              _glassCard(
                                child: TextFormField(
                                  controller: _hobbiesController,
                                  enabled: _isEditing,
                                  minLines: 3,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.done,
                                  decoration: _modernDecoration(
                                    theme: theme,
                                    label: 'Hobbies',
                                    icon: Icons.favorite_rounded,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Please enter hobbies.'
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 26),
                              SizedBox(
                                height: 56,
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _isSaving || !_isEditing
                                      ? null
                                      : _saveAndContinue,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: SaathiBeige.accentDeep,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    _isSaving
                                        ? 'Saving...'
                                        : 'Save changes',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: SaathiBeige.surfaceElevated.withValues(
                        alpha: 0.98,
                      ),
                      border: Border(
                        top: BorderSide(
                          color: SaathiBeige.accent.withValues(alpha: 0.18),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: SaathiBeige.charcoal.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      minimum: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _confirmLogout,
                            icon: Icon(
                              Icons.logout_rounded,
                              color: scheme.error,
                            ),
                            label: Text(
                              'Logout',
                              style: TextStyle(
                                color: scheme.error,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: scheme.error.withValues(alpha: 0.45),
                              ),
                              backgroundColor: SaathiBeige.cream.withValues(
                                alpha: 0.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
