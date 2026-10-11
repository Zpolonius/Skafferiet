import { test, expect, flt } from '../helpers/fixtures';
import { seedHousehold } from '../helpers/emulator';
import { login } from '../helpers/app';

test('en seedet bruger kan logge ind og ser hjemskærmen', async ({ page }) => {
  const user = await seedHousehold();
  await login(page, user);
  await expect(flt(page, 'Dagens Plan')).toBeVisible();
  await expect(flt(page, 'Se hele ugen')).toBeVisible();
});
