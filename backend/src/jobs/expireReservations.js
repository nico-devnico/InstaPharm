const reservationService = require('../services/reservationService');

async function main() {
  const result = await reservationService.expireStale();
  // eslint-disable-next-line no-console
  console.log(JSON.stringify(result));
  process.exit(0);
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exit(1);
});
