import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Shared by settings, the profile picker and AI-initiated profile switches.
/// The entered PIN stays in this dialog and is never sent to an AI service.
Future<bool> confirmProfilePin(BuildContext context, Profile profile) async {
  if (profile.pin == null || profile.pin!.isEmpty) return true;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PinDialog(profile: profile),
      ) ==
      true;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.profile});
  final Profile profile;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  bool _wrong = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == widget.profile.pin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.profile.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.profilePinPrompt),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              errorText: _wrong ? l10n.profilePinWrong : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.ok)),
      ],
    );
  }
}
