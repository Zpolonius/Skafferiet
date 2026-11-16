import { test, expect, flt } from '../helpers/fixtures';
import { patchDoc, readMealSlot, seedHousehold, seedMealPlan } from '../helpers/emulator';
import { login, openTab, selectPlanDay, typeInto } from '../helpers/app';

/**
 * #37: husstanden kan lade madplanen starte på en anden dag end mandag. Lagringen
 * er uændret (ét dokument pr. mandag), så en søndagsstart-uge består af søndagen
 * fra den forrige mandags-uge og mandag-lørdag fra den næste.
 */
const thursday = new Date(2026, 9, 15, 12, 0); // torsdag 15. okt. 2026
const sunday = new Date(2026, 9, 11); // første dag i plan-ugen 11.-17. okt. (dokument 2026-10-05)
const monday = new Date(2026, 9, 12); // dokument 2026-10-12
const saturday = new Date(2026, 9, 17); // dokument 2026-10-12
const nextSunday = new Date(2026, 9, 18); // næste plan-uge (dokument 2026-10-12)

async function addOwnMeal(page: import('@playwright/test').Page, text: string): Promise<void> {
  await flt(page, 'Tilføj aftensmad').click();
  await expect(flt(page, 'Tilføj eget måltid')).toBeVisible();
  await typeInto(page, 'Hvad skal I have at spise', text);
  await page.getByRole('button', { name: 'Gem måltid' }).click();
  await expect(flt(page, text)).toBeVisible();
}

test.describe('madplanens startdag (#37)', () => {
  test('søndagsstart: planen viser søndagen først, og nye måltider lander i det rigtige dokument', async ({
    page,
  }) => {
    const user = await seedHousehold();
    await patchDoc(`households/${user.householdId}`, { mealPlanStartWeekday: 7 });
    // Eksisterende mandags-uger, uændret lagring.
    await seedMealPlan(
      user.householdId,
      {
        Mandag: { dinner: { directEntry: 'Gammel mandag e2e' } },
        Søndag: { lunch: { directEntry: 'Søndagsfrokost e2e' } },
      },
      sunday,
    );
    await seedMealPlan(
      user.householdId,
      {
        Mandag: { dinner: { directEntry: 'Mandagsgryde e2e' } },
        Søndag: { dinner: { directEntry: 'Næste søndag e2e' } },
        Lørdag: { dinner: { directEntry: 'Lørdagspizza e2e' } },
      },
      monday,
    );

    await page.clock.setFixedTime(thursday);
    await login(page, user);
    await openTab(page, 'Madplan');

    // Planen åbner på i dag og er søn 11.-lør 17. okt. (uge 42).
    await expect(flt(page, 'Uge 42, 11. til 17. oktober, denne uge')).toBeVisible();
    const sun = await page.getByRole('button', { name: /^Søndag 11\./ }).first().boundingBox();
    const mon = await page.getByRole('button', { name: /^Mandag 12\./ }).first().boundingBox();
    const sat = await page.getByRole('button', { name: /^Lørdag 17\./ }).first().boundingBox();
    expect(sun!.x).toBeLessThan(mon!.x);
    expect(mon!.x).toBeLessThan(sat!.x);

    // Søndagen kommer fra den forrige mandags-uge, mandagen fra den næste.
    await selectPlanDay(page, 'Søndag', sunday);
    await expect(flt(page, 'Søndagsfrokost e2e')).toBeVisible();
    await selectPlanDay(page, 'Mandag', monday);
    await expect(flt(page, 'Mandagsgryde e2e')).toBeVisible();
    await expect(flt(page, 'Gammel mandag e2e')).toHaveCount(0);

    // Et nyt måltid på søndag lander i den forrige mandags dokument ...
    await selectPlanDay(page, 'Søndag', sunday);
    await addOwnMeal(page, 'Søndagsmiddag e2e');
    await expect
      .poll(() => readMealSlot(user.householdId, 'Søndag', 'dinner', sunday))
      .toEqual({ recipeId: null, directEntry: 'Søndagsmiddag e2e' });
    // ... og rører ikke søndagen i næste uges dokument.
    expect(await readMealSlot(user.householdId, 'Søndag', 'dinner', nextSunday)).toEqual({
      recipeId: null,
      directEntry: 'Næste søndag e2e',
    });

    // Lørdagen hører til den næste mandags dokument (kun læst; ét skrivetrin pr. test
    // holder testen robust mod tabte tastetryk).
    await selectPlanDay(page, 'Lørdag', saturday);
    await expect(flt(page, 'Lørdagspizza e2e')).toBeVisible();
    expect(await readMealSlot(user.householdId, 'Lørdag', 'dinner', sunday)).toBeUndefined();
  });

  test('uden indstilling (eksisterende husstand): mandag først, som før', async ({ page }) => {
    const user = await seedHousehold();
    await seedMealPlan(user.householdId, { Mandag: { dinner: { directEntry: 'Mandagsgryde e2e' } } }, monday);

    await page.clock.setFixedTime(thursday);
    await login(page, user);
    await openTab(page, 'Madplan');
    await expect(flt(page, 'Uge 42, 12. til 18. oktober, denne uge')).toBeVisible();
    await selectPlanDay(page, 'Mandag', monday);
    await expect(flt(page, 'Mandagsgryde e2e')).toBeVisible();
  });
});
