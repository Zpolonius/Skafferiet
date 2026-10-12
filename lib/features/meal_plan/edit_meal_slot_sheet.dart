import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/meal_plan.dart';
import '../../core/models/meal_type.dart';
import '../../core/models/recipe.dart';
import '../../core/theme/theme_context.dart';
import '../../shared/widgets/app_bottom_sheet.dart';
import '../recipes/recipes_provider.dart';
import 'meal_plan_provider.dart';
import 'recipe_picker.dart';
import 'slot_write.dart';

/// Åbnes når man trykker på et udfyldt måltid i madplanen: viser det nuværende
/// måltid og lader brugeren se opskriften, skifte måltid eller fjerne det.
class EditMealSlotSheet extends ConsumerStatefulWidget {
  /// Dagsnøglen madplanen bruger (fx 'Tirsdag').
  final String day;
  final MealType mealType;
  final MealSlot slot;

  const EditMealSlotSheet({
    super.key,
    required this.day,
    required this.mealType,
    required this.slot,
  });

  /// Teksten der beskriver [slot] for brugeren og skærmlæsere. [recipesFailed]:
  /// opskrifterne kunne ikke hentes, så et id aldrig bliver til en titel.
  static String describe(MealSlot slot, {bool recipesFailed = false}) {
    final recipe = slot.recipe;
    if (recipe != null) return recipe.title;
    if (slot.missingRecipe) return 'Opskriften findes ikke længere';
    final text = slot.directEntry;
    if (text != null && text.isNotEmpty) return text;
    return recipesFailed ? 'Opskriften kunne ikke hentes' : 'Henter opskrift…';
  }

  @override
  ConsumerState<EditMealSlotSheet> createState() => _EditMealSlotSheetState();
}

class _EditMealSlotSheetState extends ConsumerState<EditMealSlotSheet> {
  static const _errorText =
      'Kunne ikke gemme ændringen. Tjek din forbindelse og prøv igen.';

  final _textController = TextEditingController();

  bool _replacing = false;
  bool _ownMeal = false;
  bool _busy = false;
  String? _error;
  // Ugen måltidet står i (absolut), så "Fortryd" skriver til samme uge selv om
  // brugeren når at skifte uge eller det bliver mandag.
  late final String _weekId;

  @override
  void initState() {
    super.initState();
    _weekId = ref.read(mealPlanProvider.notifier).currentWeekId();
  }

  /// Seneste kendte indhold i pladsen (opdateres i build fra planen).
  late MealSlot _live = widget.slot;
  bool _closingRemote = false;
  bool _recipesFailed = false;

  static bool _isEmpty(MealSlot s) =>
      s.recipe == null &&
      s.recipeId == null &&
      !s.missingRecipe &&
      s.directEntry == null;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Kører en skrivning. Knapperne er låst mens den udstedes. Svarer serveren
  /// hurtigt med en fejl, bliver arket åbent med en dansk besked. Ellers (fx
  /// offline) lukkes arket uden at vente på serveren, og en senere fejl meldes
  /// på den app-brede [ScaffoldMessenger]. Returnerer true hvis arket skal lukkes.
  Future<bool> _run(Future<void> write) async {
    if (_busy) return false;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = context.colors.error;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await awaitSlotWrite(write, onLateError: (_) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: const Text('Ændringen kunne ikke gemmes og er rullet tilbage.'),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
        ));
      });
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorText;
        });
      }
      return false;
    }
  }

  Future<void> _remove() async {
    final notifier = ref.read(mealPlanProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final errorColor = context.colors.error;
    final day = widget.day;
    final key = widget.mealType.key;
    final previous = _live;
    final weekId = _weekId;
    final label = widget.mealType.label;

    // Huskes, så Fortryd ved om serveren har nået at bekræfte sletningen.
    var removeConfirmed = false;
    final removeWrite = notifier.updateSlot(day, key);
    removeWrite.then<void>((_) {
      removeConfirmed = true;
    }, onError: (Object _) {});

    final ok = await _run(removeWrite);
    if (!ok) return;
    if (mounted) navigator.pop();

    Future<void> restore() async {
      try {
        await notifier.restoreSlot(day, key, previous,
            weekId: weekId, ownRemovePending: !removeConfirmed);
      } catch (e) {
        final changed = SlotChangedException.matches(e);
        messenger.showSnackBar(SnackBar(
          content: Text(changed
              ? 'Måltidet er ændret i mellemtiden – kunne ikke fortryde.'
              : 'Kunne ikke fortryde. Prøv igen.'),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: changed
              ? null
              : SnackBarAction(label: 'Prøv igen', onPressed: restore),
        ));
      }
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$label fjernet fra ${day.toLowerCase()}'),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Fortryd', onPressed: restore),
      ));
  }

  /// Gemmer enten en opskrift eller en tekst — aldrig begge.
  Future<void> _replaceWith({Recipe? recipe, String? text}) async {
    assert((recipe == null) != (text == null));
    final notifier = ref.read(mealPlanProvider.notifier);
    final navigator = Navigator.of(context);
    final ok = await _run(recipe != null
        ? notifier.updateSlot(widget.day, widget.mealType.key, recipe: recipe)
        : notifier.updateSlot(widget.day, widget.mealType.key,
            directEntry: text!.trim()));
    if (ok && mounted) navigator.pop();
  }

  void _openRecipe(String id) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/recipes/$id');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    // Følg planen live, så arket aldrig viser (eller fortryder til) et måltid
    // som et andet medlem allerede har ændret.
    final live = ref.watch(mealPlanProvider.select((s) {
      final plan = s.valueOrNull;
      if (plan == null) return null;
      return plan.days[widget.day]?.slot(widget.mealType) ?? MealSlot();
    }));
    _live = live ?? widget.slot;
    final unresolved =
        _live.recipeId != null && _live.recipe == null && !_live.missingRecipe;
    _recipesFailed =
        unresolved && ref.watch(recipesProvider.select((r) => r.hasError));
    if (_isEmpty(_live) && !_busy && !_replacing && !_closingRemote) {
      _closingRemote = true;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(const SnackBar(
          content: Text('Måltidet er fjernet af en anden'),
          behavior: SnackBarBehavior.floating,
        ));
      });
    }

    return PopScope(
      canPop: !_busy,
      child: Container(
        padding: EdgeInsets.only(
          bottom: sheetBottomInset(context) + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  _replacing
                      ? 'Skift ${widget.mealType.label.toLowerCase()} · ${widget.day}'
                      : '${widget.mealType.label} · ${widget.day}',
                  style: text.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              if (_replacing)
                ..._replaceBody(context)
              else
                ..._overviewBody(context),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: text.bodyMedium?.copyWith(color: colors.error)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _overviewBody(BuildContext context) {
    final colors = context.colors;
    final slot = _live;
    final recipe = slot.recipe;
    final title =
        EditMealSlotSheet.describe(slot, recipesFailed: _recipesFailed);
    final subtitle =
        recipe != null ? '${recipe.calories} kcal • ${recipe.time}' : null;
    final style = context.text.titleMedium?.copyWith(
      color: slot.missingRecipe ? colors.outline : null,
    );

    return [
      // Læses op som ét udsagn og meldes ved åbning af arket.
      Semantics(
        container: true,
        liveRegion: true,
        label:
            'Nuværende måltid: $title${subtitle != null ? ', $subtitle' : ''}',
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                if (recipe != null)
                  RecipeThumb(imageUrl: recipe.imageUrl)
                else
                  Icon(
                    slot.missingRecipe ? Icons.link_off : Icons.edit_note,
                    color: colors.outline,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: style),
                      if (subtitle != null)
                        Text(subtitle, style: context.text.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (recipe != null) ...[
        _ActionButton.outlined(
          icon: Icons.menu_book_outlined,
          label: 'Se opskrift',
          onPressed: _busy ? null : () => _openRecipe(recipe.id),
        ),
        const SizedBox(height: 12),
      ],
      _ActionButton.filled(
        icon: Icons.swap_horiz,
        label: 'Skift',
        onPressed: _busy ? null : () => setState(() => _replacing = true),
      ),
      const SizedBox(height: 12),
      _ActionButton.outlined(
        icon: Icons.delete_outline,
        label: 'Fjern fra madplanen',
        color: colors.error,
        onPressed: _busy ? null : _remove,
      ),
    ];
  }

  List<Widget> _replaceBody(BuildContext context) {
    return [
      if (_isEmpty(_live)) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            'Måltidet er fjernet af en anden – du kan stadig gemme et nyt.',
            style: context.text.bodyMedium?.copyWith(color: context.colors.error),
          ),
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Opskrift')),
            ButtonSegment(value: true, label: Text('Eget måltid')),
          ],
          selected: {_ownMeal},
          style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 48))),
          onSelectionChanged:
              _busy ? null : (v) => setState(() => _ownMeal = v.first),
        ),
      ),
      const SizedBox(height: 16),
      if (_ownMeal) ..._ownMealBody(context) else ..._recipePicker(context),
      const SizedBox(height: 12),
      _ActionButton.text(
        label: 'Tilbage',
        onPressed: _busy ? null : () => setState(() => _replacing = false),
      ),
    ];
  }

  List<Widget> _ownMealBody(BuildContext context) {
    return [
      TextField(
        controller: _textController,
        enabled: !_busy,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Hvad skal I spise?',
          hintText: 'F.eks. Rugbrød med ost eller Takeout',
          prefixIcon: Icon(Icons.edit_note),
        ),
      ),
      const SizedBox(height: 16),
      _ActionButton.filled(
        icon: Icons.check,
        label: 'Gem',
        onPressed: _busy || _textController.text.trim().isEmpty
            ? null
            : () => _replaceWith(text: _textController.text),
      ),
    ];
  }

  List<Widget> _recipePicker(BuildContext context) {
    return [
      RecipePicker(
        enabled: !_busy,
        currentRecipeId: _live.recipeId,
        onPick: (recipe) => _replaceWith(recipe: recipe),
      ),
    ];
  }
}

/// Fuld bredde knap på mindst 48 dp med tekst (ikon er kun pynt).
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onPressed;
  final _Kind kind;

  const _ActionButton.filled({required this.label, this.icon, this.onPressed})
      : kind = _Kind.filled,
        color = null;
  const _ActionButton.outlined(
      {required this.label, this.icon, this.color, this.onPressed})
      : kind = _Kind.outlined;
  const _ActionButton.text({required this.label, this.onPressed})
      : kind = _Kind.text,
        icon = null,
        color = null;

  @override
  Widget build(BuildContext context) {
    const size = Size(double.infinity, 48);
    final child = Text(label);
    final Widget button;
    switch (kind) {
      case _Kind.filled:
        final style = FilledButton.styleFrom(minimumSize: size);
        button = icon == null
            ? FilledButton(onPressed: onPressed, style: style, child: child)
            : FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: Icon(icon),
                label: child);
      case _Kind.outlined:
        final style =
            OutlinedButton.styleFrom(minimumSize: size, foregroundColor: color);
        button = icon == null
            ? OutlinedButton(onPressed: onPressed, style: style, child: child)
            : OutlinedButton.icon(
                onPressed: onPressed,
                style: style,
                icon: Icon(icon),
                label: child);
      case _Kind.text:
        button = TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(minimumSize: size),
          child: child,
        );
    }
    return button;
  }
}

enum _Kind { filled, outlined, text }
