import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../core/models/board_note.dart';
import '../../shared/utils/image_upload_service.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../profile/household_provider.dart';
import 'board_policy.dart';
import 'board_provider.dart';

enum _NoteKind { text, photo, checklist }

/// Åbner formularen til en ny seddel. Returnerer `true`, hvis en seddel blev
/// sat op.
Future<bool?> showAddBoardNoteSheet(BuildContext context) {
  return showAppBottomSheet<bool>(
    context: context,
    builder: (_) => const AddBoardNoteSheet(),
  );
}

class AddBoardNoteSheet extends ConsumerStatefulWidget {
  const AddBoardNoteSheet({super.key});

  @override
  ConsumerState<AddBoardNoteSheet> createState() => _AddBoardNoteSheetState();
}

class _AddBoardNoteSheetState extends ConsumerState<AddBoardNoteSheet> {
  _NoteKind _kind = _NoteKind.text;

  final _textController = TextEditingController();
  final _captionController = TextEditingController();
  final _titleController = TextEditingController();
  final List<TextEditingController> _itemControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  String? _imageUrl;
  bool _isUploading = false;
  bool _isSaving = false;
  bool _imageSaved = false;
  String? _error;

  // Gemmes i initState, så billedet kan ryddes op i dispose, hvor `ref`
  // ikke længere må bruges.
  late final BoardNotifier _board;

  @override
  void initState() {
    super.initState();
    _board = ref.read(boardProvider.notifier);
    for (final c in [_textController, _captionController, _titleController, ..._itemControllers]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    // Et uploadet billede, der aldrig blev til en seddel, slettes igen.
    final orphan = _imageUrl;
    if (orphan != null && !_imageSaved) _board.discardImage(orphan);

    for (final c in [_textController, _captionController, _titleController, ..._itemControllers]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() => _error = null);

  /// Fejl i det udfyldte, eller `null` hvis sedlen kan gemmes.
  String? get _validationError => switch (_kind) {
        _NoteKind.text => BoardPolicy.validateText(_textController.text),
        _NoteKind.photo => _imageUrl == null
            ? 'Vælg et billede'
            : BoardPolicy.validateCaption(_captionController.text),
        _NoteKind.checklist => BoardPolicy.validateChecklist(
            _titleController.text,
            _itemControllers.map((c) => c.text).toList(),
          ),
      };

  bool get _canSave => !_isSaving && !_isUploading && _validationError == null;

  Future<void> _pickImage() async {
    final householdId = ref.read(householdProvider).householdId;
    if (householdId == null) {
      setState(() => _error = 'Du skal være med i en husstand for at dele billeder');
      return;
    }
    final previous = _imageUrl;
    setState(() {
      _isUploading = true;
      _error = null;
    });
    try {
      final url = await ImageUploadService.pickAndUpload(
        context,
        storagePath: 'households/$householdId/board',
      );
      if (url == null) return;
      if (!mounted) {
        _board.discardImage(url);
        return;
      }
      setState(() => _imageUrl = url);
      if (previous != null) _board.discardImage(previous);
    } catch (_) {
      if (mounted) setState(() => _error = 'Kunne ikke uploade billedet. Prøv igen.');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      switch (_kind) {
        case _NoteKind.text:
          await _board.addTextNote(_textController.text);
        case _NoteKind.photo:
          await _board.addPhotoNote(_imageUrl!, caption: _captionController.text);
          _imageSaved = true;
        case _NoteKind.checklist:
          await _board.addChecklistNote(
            _titleController.text,
            _itemControllers.map((c) => c.text).toList(),
          );
      }
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kunne ikke gemme sedlen. Tjek din forbindelse og prøv igen.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addItem() {
    if (_itemControllers.length >= BoardNoteLimits.checklistItemsMax) return;
    setState(() => _itemControllers.add(TextEditingController()..addListener(_onChanged)));
  }

  void _removeItem(int index) {
    if (_itemControllers.length <= 1) return;
    final c = _itemControllers.removeAt(index);
    setState(() {});
    // Feltet bruger stadig controlleren, indtil skærmen er bygget om.
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(context) + 24,
        top: 16,
        left: 24,
        right: 24,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Ny seddel', style: textTheme.displayMedium)),
                IconButton(
                  tooltip: 'Luk',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Gap(16),
            SegmentedButton<_NoteKind>(
              segments: const [
                ButtonSegment(value: _NoteKind.text, icon: Icon(Icons.notes), label: Text('Tekst')),
                ButtonSegment(
                    value: _NoteKind.photo,
                    icon: Icon(Icons.photo_outlined),
                    label: Text('Billede')),
                ButtonSegment(
                    value: _NoteKind.checklist, icon: Icon(Icons.checklist), label: Text('Liste')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: _isSaving
                  ? null
                  : (s) => setState(() {
                        _kind = s.first;
                        _error = null;
                      }),
            ),
            const Gap(20),
            ...switch (_kind) {
              _NoteKind.text => _buildTextFields(),
              _NoteKind.photo => _buildPhotoFields(cs),
              _NoteKind.checklist => _buildChecklistFields(cs),
            },
            if (_error != null) ...[
              const Gap(12),
              Text(
                _error!,
                style: textTheme.bodyMedium?.copyWith(color: cs.error, fontSize: 14),
              ),
            ],
            const Gap(24),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _isSaving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Text('Sæt på tavlen'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTextFields() => [
        TextField(
          key: const Key('board_text_field'),
          controller: _textController,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: BoardNoteLimits.textMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Skriv en besked til husstanden…',
          ),
        ),
      ];

  List<Widget> _buildPhotoFields(ColorScheme cs) => [
        Semantics(
          button: true,
          label: _imageUrl == null ? 'Vælg billede' : 'Skift billede',
          child: InkWell(
            onTap: _isUploading || _isSaving ? null : _pickImage,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              height: 180,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: _isUploading
                  ? const Center(child: CircularProgressIndicator())
                  : _imageUrl == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, size: 36, color: cs.primary),
                            const Gap(8),
                            Text('Tryk for at vælge et billede',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(imageUrl: _imageUrl!, fit: BoxFit.cover),
                        ),
            ),
          ),
        ),
        const Gap(16),
        TextField(
          controller: _captionController,
          maxLength: BoardNoteLimits.captionMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Billedtekst (valgfri)'),
        ),
      ];

  List<Widget> _buildChecklistFields(ColorScheme cs) => [
        TextField(
          controller: _titleController,
          autofocus: true,
          maxLength: BoardNoteLimits.checklistTitleMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Overskrift, fx "Husk til weekenden"'),
        ),
        const Gap(4),
        for (var i = 0; i < _itemControllers.length; i++)
          Padding(
            key: ObjectKey(_itemControllers[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.check_box_outline_blank, color: cs.outline),
                const Gap(8),
                Expanded(
                  child: TextField(
                    controller: _itemControllers[i],
                    maxLength: BoardNoteLimits.checklistItemMax,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Punkt ${i + 1}',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fjern punkt',
                  onPressed: _itemControllers.length > 1 ? () => _removeItem(i) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed:
                _itemControllers.length < BoardNoteLimits.checklistItemsMax ? _addItem : null,
            icon: const Icon(Icons.add),
            label: const Text('Tilføj punkt'),
          ),
        ),
      ];
}
