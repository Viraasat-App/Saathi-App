import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'otp_verification_screen.dart';
import '../services/auth_service.dart';
import '../theme/saathi_beige_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();

  final AuthService _authService = AuthService.instance;

  /// Default India (+91); full ISO list comes from `country_code_picker`.
  CountryCode _countryCode = CountryCode.fromCountryCode('IN');

  int _minNationalDigits = 6;
  int _maxNationalDigits = 15;

  bool _isSendingOtp = false;
  late bool _useDevelopmentMode;

  @override
  void initState() {
    super.initState();
    _useDevelopmentMode = true;
    _authService.setOtpMode(useDevelopmentOtp: true);
    _applyCountryConstraints(_countryCode);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// E.164: selected dial code + national digits (leading 0 stripped).
  String _composeE164Phone() {
    final rawDial = _countryCode.dialCode ?? '+91';
    final dialDigits = rawDial.replaceAll(RegExp(r'\D'), '');
    var national = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (national.startsWith('0')) {
      national = national.substring(1);
    }
    return '+$dialDigits$national';
  }

  void _applyCountryConstraints(CountryCode country) {
    final dial = country.dialCode ?? '+91';
    // Minimal production-friendly defaults:
    // - India: 10-digit national number
    // - US (+1): 10 digits
    // - UK (+44): 10-11 digits (allow both)
    // - Otherwise: 6-15 digits (E.164 national significant digits range)
    if (dial == '+91') {
      _minNationalDigits = 10;
      _maxNationalDigits = 10;
      return;
    }
    if (dial == '+1') {
      _minNationalDigits = 10;
      _maxNationalDigits = 10;
      return;
    }
    if (dial == '+44') {
      _minNationalDigits = 10;
      _maxNationalDigits = 11;
      return;
    }

    _minNationalDigits = 6;
    _maxNationalDigits = 15;
  }

  Future<void> _sendOtp() async {
    if (_isSendingOtp) return;

    final national = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (national.isEmpty) {
      _showMessage('Please enter your mobile number.');
      return;
    }
    if (national.length < _minNationalDigits ||
        national.length > _maxNationalDigits) {
      _showMessage(
        'Enter a valid mobile number for ${_countryCode.dialCode ?? "+91"} '
        '(min $_minNationalDigits–max $_maxNationalDigits digits).',
      );
      return;
    }

    final fullPhone = _composeE164Phone();
    _authService.setOtpMode(useDevelopmentOtp: _useDevelopmentMode);

    setState(() {
      _isSendingOtp = true;
    });

    final result = await _authService.sendOtp(fullPhone);

    if (!mounted) return;

    switch (result) {
      case SendOtpFailure(:final message):
        setState(() {
          _isSendingOtp = false;
        });
        _showMessage(message);
      case SendOtpCodeSent(:final normalizedPhone):
        setState(() => _isSendingOtp = false);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => OtpVerificationScreen(phoneNumber: normalizedPhone),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isSendingOtp;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Phone login'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: SaathiBeige.charcoal,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SaathiBeige.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Phone Number',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your phone number to continue',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            _ModeOptionCard(
                              label: 'DEV Mode',
                              subtitle: 'Use fake OTP',
                              selected: _useDevelopmentMode,
                              enabled: !busy,
                              onTap: () {
                                setState(() => _useDevelopmentMode = true);
                                _authService.setOtpMode(
                                  useDevelopmentOtp: true,
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            _ModeOptionCard(
                              label: 'PROD Mode',
                              subtitle: 'Use real OTP SMS',
                              selected: !_useDevelopmentMode,
                              enabled: !busy,
                              onTap: () {
                                setState(() => _useDevelopmentMode = false);
                                _authService.setOtpMode(
                                  useDevelopmentOtp: false,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.35),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 116,
                              child: Center(
                                child: CountryCodePicker(
                                  onChanged: busy
                                      ? null
                                      : (CountryCode code) {
                                          setState(() {
                                            _countryCode = code;
                                            _applyCountryConstraints(code);
                                          });
                                        },
                                  initialSelection: 'IN',
                                  favorite: const ['IN'],
                                  showFlag: true,
                                  showDropDownButton: true,
                                  padding: EdgeInsets.zero,
                                  margin: EdgeInsets.zero,
                                  flagWidth: 20,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                  enabled: !busy,
                                  comparator: (a, b) {
                                    final ad = int.tryParse(
                                      (a.dialCode ?? '').replaceAll('+', ''),
                                    );
                                    final bd = int.tryParse(
                                      (b.dialCode ?? '').replaceAll('+', ''),
                                    );
                                    return (ad ?? 0).compareTo(bd ?? 0);
                                  },
                                ),
                              ),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: scheme.outline.withValues(alpha: 0.35),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(
                                    _maxNationalDigits,
                                  ),
                                ],
                                textInputAction: TextInputAction.done,
                                enabled: !busy,
                                minLines: null,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.center,
                                style: Theme.of(context).textTheme.titleMedium,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  hintText: '9876543210',
                                  hintStyle: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.65),
                                      ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: busy ? null : _sendOtp,
                          child: Text(_isSendingOtp ? 'Sending…' : 'Send OTP'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _ModeOptionCard extends StatelessWidget {
  const _ModeOptionCard({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedBg = scheme.primary.withValues(alpha: 0.12);
    final selectedBorder = scheme.primary.withValues(alpha: 0.6);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedBg : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? selectedBorder : scheme.outline.withValues(alpha: 0.25),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected ? scheme.primary : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              selected ? 'Selected' : 'Tap to select',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
