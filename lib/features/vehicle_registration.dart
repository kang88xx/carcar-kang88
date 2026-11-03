import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/repository.dart';
import '../shared/components.dart';

class VehicleRegistrationDialog extends StatefulWidget {
  const VehicleRegistrationDialog({super.key, required this.controller});
  final AppController controller;

  @override
  State<VehicleRegistrationDialog> createState() =>
      _VehicleRegistrationDialogState();
}

class _VehicleRegistrationDialogState extends State<VehicleRegistrationDialog> {
  final _form = GlobalKey<FormState>();
  final _plateKey = GlobalKey<FormFieldState<String>>();
  final _fields = List.generate(4, (_) => TextEditingController());
  String? _checkedPlate, _notice, _error;
  bool _checking = false, _saving = false;
  int _revision = 0;

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _plateChanged(String _) {
    setState(() {
      _revision++;
      _checkedPlate = null;
      _notice = null;
      _error = null;
    });
  }

  Future<void> _check() async {
    if (_checking || _saving || !_plateKey.currentState!.validate()) return;
    final plate = _fields[1].text.trim();
    final revision = _revision;
    setState(() {
      _checking = true;
      _checkedPlate = null;
      _error = null;
      _notice = null;
    });
    try {
      final available = await widget.controller.repository.isPlateAvailable(
        plate,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _checkedPlate = available ? plate : null;
        _notice = available ? '등록할 수 있는 차량 번호예요.' : null;
        _error = available ? null : '이미 등록된 차량이에요. 처음 등록한 가족에게 초대를 받아 주세요.';
      });
    } on Object catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _checking ||
        _checkedPlate != _fields[1].text.trim() ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.createVehicle(
        _fields[2].text,
        _fields[1].text,
        _fields[0].text,
        _fields[3].text,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _checkedPlate = null;
          _notice = null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['차량 별명', '차량 번호', '아파트 이름', '내 이름'];
    const hints = ['예: 우리 가족 차', '예: 123가 4567', '예: 우리집 아파트', '가족에게 표시할 이름'];
    const lengths = [40, 20, 60, 40];
    return PopScope(
      canPop: !_saving,
      child: SheetDialog(
        title: '새 차량 등록',
        subtitle: '차량은 한 대만 연결할 수 있어요. 이미 가족이 등록했다면 초대 코드로 참여해 주세요.',
        onClose: _saving ? null : () => Navigator.pop(context, false),
        maxWidth: 500,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 4; i++) ...[
                TextFormField(
                  key: i == 1 ? _plateKey : null,
                  controller: _fields[i],
                  enabled: !_saving,
                  maxLength: lengths[i],
                  onChanged: i == 1 ? _plateChanged : null,
                  decoration: InputDecoration(
                    labelText: labels[i],
                    hintText: hints[i],
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '${labels[i]}을(를) 입력해 주세요.'
                      : null,
                ),
                if (i == 1) ...[
                  OutlinedButton(
                    onPressed: _checking || _saving ? null : _check,
                    child: Text(_checking ? '확인 중…' : '차량 번호 중복 확인'),
                  ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: StatusNotice(_notice!),
                    ),
                ],
                const SizedBox(height: 16),
              ],
              if (_error != null) StatusNotice(_error!, error: true),
              BusyButton(
                label: '차량 등록하기',
                onPressed: _checkedPlate == null || _checking ? null : _save,
                busy: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
