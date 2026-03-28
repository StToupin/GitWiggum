const { test, expect } = require('@playwright/test');

test('auth schema boot smoke', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: "It's working!" })).toBeVisible();
});
