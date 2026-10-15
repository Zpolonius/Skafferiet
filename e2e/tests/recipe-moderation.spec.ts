import { test, expect, flt } from '../helpers/fixtures';
import { readCollection, seedHousehold, seedRecipe } from '../helpers/emulator';
import { login, openTab, typeInto } from '../helpers/app';

/**
 * #52: Bo rapporterer en af Annas delte opskrifter fra Fællesskab. Rapporten
 * gemmes under Bos bruger-ID, og opskriften forsvinder for Bo. Derefter
 * blokerer Bo Anna, så hendes anden opskrift forsvinder, mens en tredje
 * brugers opskrift bliver. Under Profil → Blokerede brugere fjerner Bo
 * blokeringen, og opskriften er tilbage (den rapporterede forbliver skjult).
 * Reglerne for rapporter, blokeringer og fjernede opskrifter testes i
 * rules_test/recipe_moderation.test.js.
 */
test('rapportér en opskrift, blokér forfatteren og fortryd blokeringen', async ({ page }) => {
  const anna = await seedHousehold({ name: 'Anna Hansen', householdName: 'Annas Skafferi' });
  const cecilie = await seedHousehold({ name: 'Cecilie Madsen', householdName: 'Cecilies Skafferi' });
  const bo = await seedHousehold({ name: 'Bo Jensen', householdName: 'Bos Skafferi' });
  const shared = (id: string, title: string, owner: typeof anna, name: string, day: number) =>
    seedRecipe({
      id,
      title,
      householdId: owner.householdId,
      createdBy: owner.uid,
      visibility: 'public',
      authorName: name,
      createdAt: new Date(`2026-03-${String(day).padStart(2, '0')}T10:00:00Z`),
    });
  await shared('r-lasagne', 'Annas lasagne', anna, 'Anna', 1);
  await shared('r-suppe', 'Annas suppe', anna, 'Anna', 2);
  await shared('r-kage', 'Cecilies kage', cecilie, 'Cecilie', 3);

  await login(page, bo);
  await openTab(page, 'Opskrifter');
  await page.getByRole('radio', { name: 'Fællesskab' }).click();
  await expect(flt(page, 'Annas lasagne')).toBeVisible();
  await expect(flt(page, 'Annas suppe')).toBeVisible();
  await expect(flt(page, 'Cecilies kage')).toBeVisible();

  // ── Rapportér Annas lasagne ───────────────────────────────────────────────
  await page.getByRole('button', { name: /Annas lasagne/ }).first().click();
  await expect(flt(page, 'af Anna')).toBeVisible();
  await page.getByRole('button', { name: 'Flere valg' }).click();
  await flt(page, 'Rapportér opskrift').click();

  const send = page.getByRole('button', { name: 'Send rapport' });
  await expect(send).toBeDisabled();
  await page.getByRole('radio', { name: /Spam eller reklame/ }).click();
  await typeInto(page, 'Kommentar (valgfri)', 'Det er reklame');
  await expect(send).toBeEnabled();
  await send.click();

  await expect
    .poll(async () => {
      const r = (await readCollection('reports')).find((x) => x.id === `r-lasagne_${bo.uid}`);
      return r ? [r.recipeId, r.reportedBy, r.reason, r.comment] : null;
    })
    .toEqual(['r-lasagne', bo.uid, 'spam', 'Det er reklame']);
  expect((await readCollection('reports')).length).toBe(1);

  await expect(flt(page, 'Tak – vi kigger på det')).toBeVisible();
  // Tilbage i Fællesskab: den rapporterede opskrift er væk for Bo.
  await expect(flt(page, 'Annas lasagne')).toHaveCount(0);
  await expect(flt(page, 'Annas suppe')).toBeVisible();
  await expect(flt(page, 'Cecilies kage')).toBeVisible();

  // ── Blokér Anna ───────────────────────────────────────────────────────────
  await page.getByRole('button', { name: /Annas suppe/ }).first().click();
  await page.getByRole('button', { name: 'Flere valg' }).click();
  await flt(page, 'Blokér Anna').click();
  await expect(flt(page, /Alle opskrifter fra Anna skjules for dig/)).toBeVisible();
  await page.getByRole('button', { name: 'Blokér', exact: true }).click();

  await expect
    .poll(async () => {
      const b = (await readCollection(`users/${bo.uid}/blocked_authors`)).find((x) => x.id === anna.uid);
      return b ? b.name : null;
    })
    .toBe('Anna');
  // Intet er skrevet på Bos profil, hvor husstanden kan læse.
  const profile = (await readCollection('users')).find((u) => u.id === bo.uid)!;
  expect(Object.keys(profile).some((k) => /block/i.test(k))).toBe(false);

  await expect(flt(page, 'Annas suppe')).toHaveCount(0);
  await expect(flt(page, 'Annas lasagne')).toHaveCount(0);
  await expect(flt(page, 'Cecilies kage')).toBeVisible();

  // ── Fortryd under Profil → Blokerede brugere ──────────────────────────────
  await page.locator('flt-semantics-host').getByText('B', { exact: true }).first().click();
  await flt(page, 'Blokerede brugere').click();
  await expect(flt(page, 'Skjult for dig')).toBeVisible();
  await expect(flt(page, 'Anna').first()).toBeVisible();
  await page.getByRole('button', { name: 'Fjern blokering af Anna' }).click();

  await expect
    .poll(async () => (await readCollection(`users/${bo.uid}/blocked_authors`)).length)
    .toBe(0);
  await expect(flt(page, 'Du har ikke blokeret nogen')).toBeVisible();

  // Tilbage til Fællesskab: Annas suppe er tilbage, den rapporterede er stadig skjult.
  await page.getByRole('button', { name: /Tilbage|Back/ }).first().click();
  await page.getByRole('button', { name: /Tilbage|Back/ }).first().click();
  await expect(flt(page, 'Annas suppe')).toBeVisible();
  await expect(flt(page, 'Cecilies kage')).toBeVisible();
  await expect(flt(page, 'Annas lasagne')).toHaveCount(0);
});
