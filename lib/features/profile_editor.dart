import 'package:flutter/material.dart';
import '../core/repository.dart';
import '../shared/components.dart';

Future<bool> openProfileEditor(
  BuildContext context,
  ParkingRepository repository,
) async =>
    await showSheetDialog<bool>(
      context,
      builder: (_) => ProfileEditorDialog(repository: repository),
    ) ??
    false;

class ProfileEditorDialog extends StatefulWidget {
  const ProfileEditorDialog({super.key, required this.repository});
  final ParkingRepository repository;

  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _loading = true, _loaded = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final name = await widget.repository.profileName();
      if (!mounted) return;
      _name.text = name;
      _loaded = true;
    } on Object catch (error) {
      if (mounted) _error = friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_loaded || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateProfileName(_name.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SheetDialog(
      title: '내 이름',
      subtitle: widget.repository.isDemo
          ? '이 기기의 체험 기록에 표시할 이름이에요.'
          : '같은 차량을 쓰는 가족에게 표시돼요.',
      onClose: _saving ? null : () => Navigator.of(context).pop(false),
      maxWidth: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_error != null)
                StatusNotice(
                  _error!,
                  error: true,
                  onRetry: _loaded ? null : _load,
                ),
              if (_loaded)
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: '가족에게 표시할 이름',
                    hintText: '예: 민수, 엄마',
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    try {
                      validatedProfileName(value ?? '');
                      return null;
                    } on AppException catch (error) {
                      return error.message;
                    }
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
            ],
            const SizedBox(height: 16),
            BusyButton(
              label: _saving ? '저장 중…' : '이름 저장',
              onPressed: _saving || !_loaded ? null : _save,
              busy: _saving,
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    ),
  );
}
