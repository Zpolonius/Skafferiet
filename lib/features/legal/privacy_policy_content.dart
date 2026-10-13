// Privatlivspolitikken — én kilde til både skærmen i appen og
// docs/PRIVACY_POLICY.md (som hostes til App Store Connect).
//
// Ret teksten her og kør derefter:
//   dart run tool/export_privacy_policy.dart
// Testen i test/features/privacy_policy_test.dart fejler, hvis de to er ude af trit.
//
// Ren Dart (ingen Flutter-import), så eksport-scriptet kan køre den.

import '../../core/app_info.dart';

class PolicySection {
  final String title;

  /// Linjer der starter med '• ' vises som punkter.
  final List<String> lines;

  const PolicySection(this.title, this.lines);
}

const privacyPolicyTitle = 'Privatlivspolitik for Skafferiet';

const privacyPolicySections = <PolicySection>[
  PolicySection('Hvem er ansvarlig', [
    '${AppInfo.dataControllerName} er dataansvarlig for de oplysninger, '
        'der behandles i Skafferiet. Du kan altid skrive til '
        '${AppInfo.contactEmail}.',
  ]),
  PolicySection('Hvilke oplysninger vi gemmer', [
    '• Konto: dit navn og din e-mail. Din adgangskode håndteres af Google '
        'Firebase, og vi kan ikke se den.',
    '• Profilbillede, hvis du vælger at tilføje et.',
    '• Hvilke måltider du vil se i din madplan.',
    '• Husstand: navn, medlemmer, antal voksne og børn, madpræferencer og indkøbsdag.',
    '• Indhold du opretter: opskrifter (også billeder og næringsindhold), '
        'indkøbsliste (også faste genkøb) og madplaner.',
    '• Varehistorik: de varer I har brugt på indkøbslisten (navn, kategori, '
        'enhed, mængde og hvor ofte og hvornår de sidst er brugt), så appen kan '
        'foreslå dem igen. Historikken bliver i husstanden, også når varer '
        'fjernes fra indkøbslisten, og du kan fjerne et forslag i appen.',
    '• Invitationer: e-mailen på den, du inviterer, og dit navn som afsender.',
    '• Delte opskrifter: vælger du at dele en opskrift med alle brugere, '
        'gemmes dit fornavn på opskriften.',
    'Vi bruger ikke reklamer, analyseværktøjer eller sporing på tværs af apps.',
  ]),
  PolicySection('Hvorfor', [
    'Oplysningerne bruges kun til at levere appen: så du kan logge ind, og så '
        'din husstand kan dele madplan, opskrifter og indkøbsliste. '
        'Grundlaget er, at behandlingen er nødvendig for at levere den '
        'tjeneste, du har bedt om (databeskyttelsesforordningens artikel '
        '6, stk. 1, litra b).',
  ]),
  PolicySection('Hvem kan se dine oplysninger', [
    '• Medlemmer af din husstand kan se dit navn, dit profilbillede og det '
        'indhold, I deler.',
    '• Når du inviterer nogen, kan de se dit navn og husstandens navn.',
    '• Deler du en opskrift med alle brugere, kan alle andre brugere af appen '
        'se og søge i den: titel, billede, ingredienser, fremgangsmåde, '
        'næringsindhold og dit fornavn. Det er frivilligt og slået fra som '
        'standard, og kun den enkelte opskrift deles. Kun den, der har lavet '
        'opskriften, kan dele den. Du kan slå deling fra igen når som helst under '
        'Rediger opskrift, så er den kun synlig for din husstand. Har du forladt '
        'husstanden, finder du opskriften under Fællesskab og vælger Stop med at dele. Andre kan gemme en kopi af en delt opskrift i deres egen '
        'husstand. Kopien er deres egen og bliver, selvom du fjerner delingen. '
        'Et billedlink, som andre allerede har åbnet, kan stadig virke, efter at '
        'du har slået deling fra.',
    '• Google Firebase opbevarer data og står for login på vores vegne. Google '
        'kan behandle data uden for EU; det sker på grundlag af '
        'EU-Kommissionens standardkontraktbestemmelser.',
    'Vi sælger eller deler aldrig dine oplysninger med andre.',
  ]),
  PolicySection('Hvor længe', [
    'Vi gemmer dine oplysninger, så længe du har en konto. Du kan slette '
        'kontoen i appen under Profil → Slet konto. Så slettes din profil, '
        'dit profilbillede og invitationer til og fra dig med det samme.',
    'Er du det eneste medlem af din husstand, slettes hele husstanden med '
        'opskrifter, indkøbsliste, varehistorik og madplaner. Er der andre medlemmer, '
        'bliver de opskrifter, du har lavet, i husstanden, så de andre ikke '
        'mister dem. Opskrifter, du har delt med alle brugere, slettes dog '
        'altid sammen med din konto. Så forsvinder de for alle, også fra din '
        'husstands madplaner. Kopier, som andre har gemt i deres egen '
        'husstand, bliver hos dem.',
  ]),
  PolicySection('Dine rettigheder', [
    'Du har ret til at få indsigt i, rettet og slettet dine oplysninger, til '
        'at få dem udleveret (dataportabilitet) og til at gøre indsigelse. '
        'Skriv til ${AppInfo.contactEmail}.',
    'Du kan klage til Datatilsynet (datatilsynet.dk).',
  ]),
  PolicySection('Ændringer', [
    'Sidst opdateret ${AppInfo.privacyPolicyUpdated}. Ændrer vi politikken, '
        'kan du altid se den nyeste udgave i appen.',
  ]),
];

/// Politikken som Markdown — til hosting, så App Store Connect kan linke til den.
String privacyPolicyMarkdown() {
  final blocks = <String>['# $privacyPolicyTitle'];
  for (final section in privacyPolicySections) {
    blocks.add('## ${section.title}');
    final bullets = <String>[];
    void flushBullets() {
      if (bullets.isEmpty) return;
      blocks.add(bullets.join('\n'));
      bullets.clear();
    }

    for (final line in section.lines) {
      if (line.startsWith('• ')) {
        bullets.add('- ${line.substring(2)}');
      } else {
        flushBullets();
        blocks.add(line);
      }
    }
    flushBullets();
  }
  return '${blocks.join('\n\n')}\n';
}
