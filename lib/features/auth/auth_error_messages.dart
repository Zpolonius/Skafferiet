/// Firebase-fejlkoder oversat til dansk. Samlet ét sted, så login, nulstil
/// adgangskode, skift adgangskode og slet konto siger det samme om den samme
/// fejl. En skærm, der har brug for en anden formulering, giver [overrides]
/// med i stedet for at ændre listen.
String authErrorMessage(
  String code, {
  required String fallback,
  Map<String, String> overrides = const {},
}) =>
    overrides[code] ?? _messages[code] ?? fallback;

const _wrongPassword = 'Forkert adgangskode.';
const _noConnection = 'Ingen forbindelse. Tjek dit internet, og prøv igen.';

const _messages = {
  'wrong-password': _wrongPassword,
  'invalid-credential': _wrongPassword,
  'INVALID_LOGIN_CREDENTIALS': _wrongPassword,
  'user-not-found': 'Ingen bruger fundet med denne e-mail.',
  'invalid-email': 'Ugyldig e-mailadresse.',
  'email-already-in-use': 'Denne e-mail er allerede i brug.',
  'weak-password': 'Adgangskoden er for svag.',
  'too-many-requests': 'For mange forsøg. Vent lidt, og prøv igen.',
  'network-request-failed': _noConnection,
  'unavailable': _noConnection,
  'requires-recent-login': 'Log ud og ind igen, og prøv så igen.',
};
