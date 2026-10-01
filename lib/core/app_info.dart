/// Oplysninger om udgiveren, som vises i privatlivspolitikken.
///
/// SKAL udfyldes før release — se APP_STORE_CHECKLIST.md. Apple afviser en
/// privatlivspolitik uden kontaktoplysninger.
abstract final class AppInfo {
  /// Den dataansvarlige: dit navn eller dit firmanavn.
  static const dataControllerName = 'Skafferiet';

  /// E-mail hvor brugere kan kontakte dig om deres data.
  static const contactEmail = 'UDFYLD-KONTAKT-EMAIL';

  /// Hvornår privatlivspolitikken sidst blev ændret.
  static const privacyPolicyUpdated = '1. oktober 2026';
}
