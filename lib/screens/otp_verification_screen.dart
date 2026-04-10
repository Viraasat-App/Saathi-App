import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart';

import '../services/auth_service.dart';
import '../services/auth_storage.dart';
import '../services/chat_history_storage.dart';
import '../theme/saathi_beige_theme.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with CodeAutoFill {
  final AuthService _authService = AuthService.instance;
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  bool _isVerifying = false;
  bool _didFinishLogin = false;

  @override
  void initState() {
    super.initState();
    _otpFocusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    cancel();
    _otpFocusNode.removeListener(_refresh);
    _otpFocusNode.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void codeUpdated() {
    final value = code?.trim() ?? '';
    if (value.isEmpty) return;
    _updateOtpCode(value);
    if (!_isVerifying && value.length >= 6) {
      _verifyOtp();
    }
  }

  void _updateOtpCode(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits == _otpController.text) return;
    _otpController.text = digits;
    _otpController.selection = TextSelection.fromPosition(
      TextPosition(offset: _otpController.text.length),
    );
    _refresh();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _completeLogin(CognitoSession session) async {
    try {
      await _authService.logAuthenticationDebug(session);
    } catch (_) {
      if (mounted) {
        _showMessage('Signed in but could not log token details.');
      }
    }

    final nextUserId = session.sub ?? '';
    if (nextUserId.isNotEmpty) {
      await ChatHistoryStorage.instance.clearIfUserChanged(nextUserId);
    }
    await AuthStorage.instance.saveSession(session);
    if (!mounted || _didFinishLogin) return;
    _didFinishLogin = true;
    Navigator.pushNamedAndRemoveUntil(context, '/profile', (route) => false);
  }

  Future<void> _verifyOtp() async {
    if (_didFinishLogin || _isVerifying) return;
    if (_otpController.text.trim().length < 6) {
      _showMessage('Enter the 6-digit OTP.');
      return;
    }

    setState(() => _isVerifying = true);
    final result = await _authService.verifyOtp(_otpController.text);

    if (!mounted) return;

    switch (result) {
      case VerifyOtpFailure(:final message):
        setState(() => _isVerifying = false);
        _showMessage(message);
      case VerifyOtpSuccess(:final session):
        setState(() => _isVerifying = false);
        await _completeLogin(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: SaathiBeige.cream,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('OTP Verification'),
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Verifying OTP',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the 6-digit code sent to ${widget.phoneNumber}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: SizedBox(
                          width: 316,
                          child: PinFieldAutoFill(
                            controller: _otpController,
                            focusNode: _otpFocusNode,
                            codeLength: 6,
                            autoFocus: true,
                            enabled: !_isVerifying,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: BoxLooseDecoration(
                              gapSpace: 8,
                              radius: const Radius.circular(10),
                              strokeWidth: 1.2,
                              strokeColorBuilder: FixedColorBuilder(
                                scheme.outline.withValues(alpha: 0.5),
                              ),
                              bgColorBuilder: FixedColorBuilder(scheme.surface),
                              textStyle: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            currentCode: _otpController.text,
                            onCodeChanged: (value) {
                              _updateOtpCode(value ?? '');
                              if (!_isVerifying && (value?.length ?? 0) >= 6) {
                                _verifyOtp();
                              }
                            },
                            onCodeSubmitted: (value) {
                              _updateOtpCode(value);
                              if (!_isVerifying && value.length >= 6) {
                                _verifyOtp();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        kDebugMode && _authService.useDevelopmentOtp
                            ? 'Development mode: enter any 6-digit code. Those digits are your user id for uploads and profile (new code → new user).'
                            : 'Auto-fill will be used if your device detects the OTP SMS.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isVerifying ? null : _verifyOtp,
                          child: Text(
                            _isVerifying ? 'Verifying…' : 'Verify OTP',
                          ),
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
