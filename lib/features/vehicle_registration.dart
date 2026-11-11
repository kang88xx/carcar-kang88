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
  // Plate, vehicle nickname, my name. The apartment name starts as a default
  // and is edited later in 설정 → 우리 주차장.
  late final _fields = [
    TextEditingController(),
    TextEditingController(text: '우리 차'),
    TextEditingController(text: widget.controller.repository.accountName),
  ];
  String? _plateError, _error;
  bool _saving = false;
  final _submit = GlobalKey();

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _plateError = null;
      _error = null;
    });
    try {
      // The server checks the plate format and uniqueness while registering.
      await widget.controller.createVehicle(
        '우리 아파트',
        _fields[0].text,
        _fields[1].text,
        _fields[2].text,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          if (isPlateError(error)) {
            _plateError = friendlyError(error);
          } else {
            _error = friendlyError(error);
          }
        });
        // The message appears above the button; with the keyboard open it may
        // push the button to press again out of view.
        if (_error != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final button = _submit.currentContext;
            if (button == null) return;
            Scrollable.ensureVisible(
              button,
              alignment: 1,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          });
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['차량 번호', '차량 별명', '내 이름'];
    const hints = ['예: 123가 4567', '예: 우리 가족 차', '가족에게 표시할 이름'];
    const lengths = [20, 40, 40];
    const missing = ['차량 번호를 입력해 주세요.', '차량 별명을 입력해 주세요.', '내 이름을 입력해 주세요.'];
    return PopScope(
      canPop: !_saving,
      child: SheetDialog(
        title: '새 차량 등록',
        onClose: _saving ? null : () => Navigator.pop(context, false),
        maxWidth: 500,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 3; i++) ...[
                TextFormField(
                  controller: _fields[i],
                  enabled: !_saving,
                  autofocus: i == 0,
                  maxLength: lengths[i],
                  textInputAction: i == 2
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onChanged: i == 0 && _plateError != null
                      ? (_) => setState(() => _plateError = null)
                      : null,
                  onFieldSubmitted: i == 2 ? (_) => _save() : null,
                  decoration: InputDecoration(
                    labelText: labels[i],
                    hintText: hints[i],
                    counterText: '',
                    errorText: i == 0 ? _plateError : null,
                    errorMaxLines: 3,
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? missing[i] : null,
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null) StatusNotice(_error!, error: true),
              BusyButton(
                key: _submit,
                label: '차량 등록하기',
                onPressed: _save,
                busy: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
