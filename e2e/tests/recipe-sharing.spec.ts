import { test, expect, flt, routeNetwork } from '../helpers/fixtures';
import { readCollection, seedHousehold, seedRecipe } from '../helpers/emulator';
import { login, openTab, typeInto } from '../helpers/app';

/**
 * #51: Anna deler en opskrift med alle brugere (valget "Del med alle
 * brugere"). Bo, i en anden husstand, finder den under Opskrifter →
 * Fællesskab, søger den frem, ser "af Anna" og gemmer en kopi i sin egen
 * husstand. At Bo ikke kan ændre eller slette originalen testes i rules_test/.
 */
test('del en opskrift, find den fra en anden husstand og gem en kopi', async ({ page, browser }, testInfo) => {
  const anna = await seedHousehold({ name: 'Anna Hansen', householdName: 'Annas Skafferi' });
  const bo = await seedHousehold({ name: 'Bo Jensen', householdName: 'Bos Skafferi' });
  // En ældre delt opskrift og 22 nyere: den ældre ligger IKKE på Fællesskabs
  // første side (20), så kun serverens titel-søgning kan finde den.
  await seedRecipe({
    id: 'r-suppe',
    title: 'Tomatsuppe',
    householdId: anna.householdId,
    createdBy: anna.uid,
    visibility: 'public',
    authorName: 'Anna',
    createdAt: new Date('2026-01-01T10:00:00Z'),
  });
  for (let i = 1; i <= 22; i++) {
    await seedRecipe({
      id: `r-nyere-${i}`,
      title: `Nyere ret ${i}`,
      householdId: anna.householdId,
      createdBy: anna.uid,
      visibility: 'public',
      authorName: 'Anna',
      createdAt: new Date(`2026-02-${String(i).padStart(2, '0')}T10:00:00Z`),
    });
  }

  // ── Anna opretter og deler ────────────────────────────────────────────────
  await login(page, anna);
  await openTab(page, 'Opskrifter');
  await page.getByRole('button', { name: 'Opret opskrift' }).first().click();
  await typeInto(page, 'Titel', 'Delt lasagne');
  await page.getByRole('switch', { name: /Del med alle brugere/ }).click();
  await page.getByRole('button', { name: 'Opret opskrift' }).last().click();

  let originalId = '';
  await expect
    .poll(async () => {
      const r = (await readCollection('recipes')).find((x) => x.title === 'Delt lasagne');
      originalId = String(r?.id ?? '');
      return r ? [r.visibility, r.authorName, r.titleLower, r.householdId] : null;
    })
    .toEqual(['public', 'Anna', 'delt lasagne', anna.householdId]);

  // ── Bo i en anden husstand ────────────────────────────────────────────────
  const context = await browser.newContext({
    baseURL: testInfo.project.use.baseURL,
    viewport: { width: 420, height: 900 },
    locale: 'da-DK',
  });
  try {
    const boPage = await context.newPage();
    await routeNetwork(boPage);
    await login(boPage, bo);
    await openTab(boPage, 'Opskrifter');

    // Bos egen liste ("Vores") har ikke Annas opskrift.
    await expect(flt(boPage, 'Delt lasagne')).toHaveCount(0);

    await boPage.getByRole('radio', { name: 'Fællesskab' }).click();
    await expect(flt(boPage, 'Delt lasagne')).toBeVisible();
    // Første side er de 20 nyeste; Tomatsuppe er ældre og ikke hentet endnu.
    await expect(flt(boPage, 'Tomatsuppe')).toHaveCount(0);

    // Søgning: serverens titel-præfiks finder den ældre opskrift.
    await typeInto(boPage, 'Søg i delte opskrifter', 'tomat');
    await expect(flt(boPage, 'Tomatsuppe')).toBeVisible();
    await expect(flt(boPage, 'Delt lasagne')).toHaveCount(0);
    // Feltet har fokus, og dets navn er nu den skrevne tekst: skriv videre i det.
    await boPage.keyboard.press('ControlOrMeta+A');
    await boPage.keyboard.press('Backspace');
    await boPage.keyboard.type('delt', { delay: 20 });
    await expect(flt(boPage, 'Delt lasagne')).toBeVisible();
    await expect(flt(boPage, 'Tomatsuppe')).toHaveCount(0);

    // Åbn: forfatterens fornavn, ingen redigering, og "Gem i vores opskrifter".
    await boPage.getByRole('button', { name: /Delt lasagne/ }).first().click();
    await expect(flt(boPage, 'af Anna')).toBeVisible();
    await expect(boPage.getByRole('button', { name: 'Rediger opskrift' })).toHaveCount(0);
    await boPage.getByRole('button', { name: 'Gem i vores opskrifter' }).click();

    await expect
      .poll(async () => {
        const copy = (await readCollection('recipes')).find((x) => x.copiedFrom === originalId);
        return copy
          ? {
              householdId: copy.householdId,
              createdBy: copy.createdBy,
              visibility: copy.visibility,
              title: copy.title,
              authorName: copy.authorName ?? null,
            }
          : null;
      })
      .toEqual({
        householdId: bo.householdId,
        createdBy: bo.uid,
        visibility: 'household',
        title: 'Delt lasagne',
        authorName: null,
      });

    // Originalen er uændret, og der er kun én kopi.
    const all = await readCollection('recipes');
    const original = all.find((x) => x.id === originalId)!;
    expect([original.householdId, original.visibility, original.createdBy]).toEqual([
      anna.householdId,
      'public',
      anna.uid,
    ]);
    expect(all.filter((x) => x.copiedFrom === originalId)).toHaveLength(1);

    await expect(flt(boPage, 'Åbn')).toBeVisible();
  } finally {
    await context.close();
  }
});
