import { test, expect, flt } from '../helpers/fixtures';
import { readMealSlot, seedHousehold, seedMealPlan } from '../helpers/emulator';
import { login, openTab, selectPlanDay, typeInto } from '../helpers/app';

/**
 * #56: en familie lavede madplanen søndag (sidste dag i ugen) og fandt den
 * væk torsdag, fordi måltiderne lå i ugen der sluttede samme dag. Urene
 * fastfryses med page.clock, så testene giver det samme hvilken dag de køres.
 */
const sunday = new Date(2026, 9, 11, 12, 0); // søndag 11. okt. 2026 (uge 41)
const saturday = new Date(2026, 9, 17, 10, 0); // lørdag 17. okt. 2026 (uge 42)
const thursday = new Date(2026, 9, 15, 12, 0); // torsdag 15. okt. 2026 (uge 42)

async function addOwnMeal(page: import('@playwright/test').Page, text: string): Promise<void> {
  await flt(page, 'Tilføj aftensmad').click();
  // Uden opskrifter åbner arket på fanen "Eget måltid".
  await expect(flt(page, 'Tilføj eget måltid')).toBeVisible();
  await typeInto(page, 'Hvad skal I have at spise', text);
  await page.getByRole('button', { name: 'Gem måltid' }).click();
  await expect(flt(page, text)).toBeVisible();
}

test.describe('madplanens uger (#56)', () => {
  test('søndag -> torsdag: planen lagt i den forkerte uge kan kopieres til denne uge', async ({ page }) => {
    const user = await seedHousehold();

    // Søndag: weekendhjælpen vises, og et måltid lægges (som brugerne gjorde) i "denne" uge.
    await page.clock.setFixedTime(sunday);
    await login(page, user);
    await openTab(page, 'Madplan');
    await expect(flt(page, 'Uge 41, 5. til 11. oktober, denne uge')).toBeVisible();
    await expect(flt(page, 'Planlægger du næste uge?')).toBeVisible();
    await selectPlanDay(page, 'Søndag', sunday);
    await addOwnMeal(page, 'Rugbrød æøå');
    await expect
      .poll(() => readMealSlot(user.householdId, 'Søndag', 'dinner', sunday))
      .toEqual({ recipeId: null, directEntry: 'Rugbrød æøå' });

    // Samme session, appen har stået åben siden søndag: torsdag kommer appen
    // tilbage i forgrunden. Ugen skal skifte af sig selv (overskrift, plan og
    // skrivninger), uden genindlæsning.
    await page.clock.setFixedTime(thursday);
    // Headless Chromium har ingen rigtig fanevisning at skifte, så siden
    // meldes skjult og derefter synlig igen (Flutter web oversætter det til
    // AppLifecycleState paused -> resumed).
    await page.evaluate(() => {
      const setVisibility = (state: 'hidden' | 'visible') => {
        Object.defineProperty(document, 'visibilityState', { value: state, configurable: true });
        Object.defineProperty(document, 'hidden', { value: state === 'hidden', configurable: true });
        document.dispatchEvent(new Event('visibilitychange'));
      };
      setVisibility('hidden');
      setVisibility('visible');
    });
    await expect(flt(page, 'Overfør til indkøb')).toBeVisible();
    await expect(flt(page, 'Uge 42, 12. til 18. oktober, denne uge')).toBeVisible();
    await expect(flt(page, 'Denne uge').first()).toBeVisible();
    await expect(flt(page, 'Planlægger du næste uge?')).toHaveCount(0); // hverdag
    await expect(flt(page, 'Sidste uge havde 1 måltid – kopiér til denne uge?')).toBeVisible();
    expect(await readMealSlot(user.householdId, 'Søndag', 'dinner', thursday)).toBeUndefined();

    await page.getByRole('button', { name: 'Kopiér', exact: true }).click();
    await expect(flt(page, '1 måltid kopieret')).toBeVisible();
    await expect(flt(page, 'Sidste uge havde')).toHaveCount(0);
    await selectPlanDay(page, 'Søndag', new Date(2026, 9, 18));
    await expect(flt(page, 'Rugbrød æøå')).toBeVisible();
    await expect
      .poll(() => readMealSlot(user.householdId, 'Søndag', 'dinner', thursday))
      .toEqual({ recipeId: null, directEntry: 'Rugbrød æøå' });
    // Forrige uge er urørt.
    expect(await readMealSlot(user.householdId, 'Søndag', 'dinner', sunday)).toEqual({
      recipeId: null,
      directEntry: 'Rugbrød æøå',
    });

    // Fortryd fjerner præcis det kopierede igen.
    await page.getByRole('button', { name: 'Fortryd' }).click();
    await expect
      .poll(() => readMealSlot(user.householdId, 'Søndag', 'dinner', thursday))
      .toEqual({ recipeId: null, directEntry: null });
    await expect(flt(page, 'Sidste uge havde 1 måltid – kopiér til denne uge?')).toBeVisible();

    // Et måltid lagt nu havner i den viste uge (torsdag er valgt) og forsvinder ikke.
    await selectPlanDay(page, 'Torsdag', thursday);
    await addOwnMeal(page, 'Torsdagsmad');
    await expect
      .poll(() => readMealSlot(user.householdId, 'Torsdag', 'dinner', thursday))
      .toEqual({ recipeId: null, directEntry: 'Torsdagsmad' });
    expect(await readMealSlot(user.householdId, 'Torsdag', 'dinner', sunday)).toBeUndefined();
  });

  test('lørdag: "Gå til næste uge" lægger planen i den kommende uge', async ({ page }) => {
    const user = await seedHousehold();
    await page.clock.setFixedTime(saturday);
    await login(page, user);
    await openTab(page, 'Madplan');
    await expect(flt(page, 'Planlægger du næste uge?')).toBeVisible();

    await page.getByRole('button', { name: 'Gå til næste uge' }).click();
    await expect(flt(page, 'Uge 43, 19. til 25. oktober, næste uge')).toBeVisible();
    await expect(flt(page, 'Planlægger du næste uge?')).toHaveCount(0);

    await selectPlanDay(page, 'Mandag', new Date(2026, 9, 19));
    await addOwnMeal(page, 'Pasta e2e');
    const nextWeek = new Date(2026, 9, 19);
    await expect
      .poll(() => readMealSlot(user.householdId, 'Mandag', 'dinner', nextWeek))
      .toEqual({ recipeId: null, directEntry: 'Pasta e2e' });
    // Intet landede i den uge, der slutter om en dag.
    expect(await readMealSlot(user.householdId, 'Mandag', 'dinner', saturday)).toBeUndefined();

    // Tilbage til denne uge med "Gå til denne uge".
    await page.getByRole('button', { name: 'Gå til denne uge' }).click();
    await expect(flt(page, 'Uge 42, 12. til 18. oktober, denne uge')).toBeVisible();
  });

  test('en tom uge uden måltider i ugen før tilbyder ikke at kopiere', async ({ page }) => {
    const user = await seedHousehold();
    await seedMealPlan(user.householdId, {}, new Date(2026, 9, 5));
    await page.clock.setFixedTime(thursday);
    await login(page, user);
    await openTab(page, 'Madplan');
    await expect(flt(page, 'Uge 42, 12. til 18. oktober, denne uge')).toBeVisible();
    await expect(flt(page, 'kopiér til denne uge')).toHaveCount(0);
  });
});
