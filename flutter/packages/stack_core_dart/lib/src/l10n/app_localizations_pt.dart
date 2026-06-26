// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appsTitle => 'Apps';

  @override
  String get refresh => 'Atualizar';

  @override
  String get archived => 'Arquivado';

  @override
  String get favoritesSection => 'Favoritos';

  @override
  String get allAppsSection => 'All apps';

  @override
  String get noAppsForAccount => 'Nenhum app encontrado para esta conta.';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get archiveAction => 'Arquivar';

  @override
  String get addedToFavorites => 'Adicionado aos favoritos';

  @override
  String get removedFromFavorites => 'Removido dos favoritos';

  @override
  String get archivedToast => 'Arquivado';

  @override
  String get unarchivedToast => 'Desarquivado';

  @override
  String get couldNotUpdateApp => 'Não foi possível atualizar o app';

  @override
  String get couldNotLoadApps => 'Não foi possível carregar os apps';

  @override
  String get noArchivedApps => 'Nenhum app arquivado.';

  @override
  String get unarchiveAction => 'Desarquivar';

  @override
  String get appFallbackTitle => 'App';

  @override
  String get appNotFound => 'App não encontrado.';

  @override
  String get favoriteAction => 'Favorito';

  @override
  String get unfavoriteAction => 'Remover dos favoritos';

  @override
  String get fieldName => 'Nome';

  @override
  String get fieldBundleId => 'Bundle ID';

  @override
  String get fieldPlatform => 'Plataforma';

  @override
  String get ratingsAndReviews => 'Avaliações e comentários';

  @override
  String appSubtitleWithPlatform(String bundleId, String platform) {
    return '$bundleId · $platform';
  }
}
