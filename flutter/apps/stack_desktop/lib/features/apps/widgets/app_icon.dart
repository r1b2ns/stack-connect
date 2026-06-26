import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

/// Renders an App Store Connect app's icon, resolved lazily via
/// [appIconProvider] (the most recent build's `iconUrl`) and cached on disk.
///
/// While the URL resolves, fails, or comes back null, a Fluent-idiomatic
/// rounded placeholder tile (a cube glyph on a subtle fill) is shown — so the
/// widget always occupies the same [size]x[size] footprint regardless of state.
class AppIcon extends ConsumerWidget {
  const AppIcon({
    required this.accountId,
    required this.appId,
    this.size = 40,
    this.radius = 8,
    super.key,
  });

  final String accountId;
  final String appId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon =
        ref.watch(appIconProvider((accountId: accountId, appId: appId)));

    final url = icon.valueOrNull;
    final child = (url == null || url.isEmpty)
        ? _Placeholder(size: size)
        : CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, _) => _Placeholder(size: size),
            errorWidget: (_, _, _) => _Placeholder(size: size),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// The rounded fallback tile shown when there is no icon to render.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: size,
      height: size,
      color: theme.resources.subtleFillColorSecondary,
      child: Icon(
        FluentIcons.cube_shape,
        size: size * 0.5,
        color: theme.resources.textFillColorSecondary,
      ),
    );
  }
}
