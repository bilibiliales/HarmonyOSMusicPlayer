const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const code = fs.readFileSync(path.join(__dirname, '../main/ets/services/ListeningFootprint.ets'), 'utf8');
const exportsUnderTest = {};
vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText,
  { exports: exportsUnderTest });
const { buildListeningPeriod: build, listeningDayBackground: background, listeningDayColor: color } = exportsUnderTest;
const now = new Date(2026, 9, 3);
const report = { startTime: new Date(2026, 8, 27).getTime(), listenTimeDistributionBlock: { durationDetails: [
  { period: '2026-09-27', duration: 42 }, { period: '2026-09-28', duration: 60 },
  { period: '2026-09-29', duration: 90 }, { period: '2026-09-30', duration: 0 }
] } };
const week = build(report, false, now);
assert.equal(week.days.length, 7);
assert.equal(week.days[0].key, '2026-09-27');
assert.equal(week.days[6].key, '2026-10-03');
assert.equal(week.totalMinutes, 192);
assert.equal(week.listenedDays, 3);
assert.equal(background(week.days[0]), 'rgba(239,35,60,0.22)');
assert.equal(color(week.days[0]), '#ff6577');
assert.equal(background(week.days[1]), '#ef233c');
assert.equal(color(week.days[1]), '#ffffff');
assert.equal(background(week.days[3]), 'transparent');
assert.equal(week.days[4].reported, false);
const leap = build({ startTime: new Date(2024, 1, 1).getTime() / 1000 }, true, now);
assert.equal(leap.days.length, 29);
assert.equal(leap.rows[0][0].day, 0);
assert.equal(leap.rows[0][4].day, 1);
assert.equal(leap.rows.flat().filter(d => d.day > 0).length, 29);
assert.equal(leap.rows.every(row => row.length === 7), true);
const month = build({ startTime: new Date(2026, 9, 1).getTime(), listenTimeBlock: { playDuration: 123 },
  listenTimeDistributionBlock: { durationDetails: [{ period: '2026-10-04', duration: 100 }] } }, true, now);
assert.equal(month.days.length, 31);
assert.equal(month.days[3].future, true);
assert.equal(month.days[3].reported, false);
assert.equal(month.totalMinutes, 123);
const unordered = build({ listenTimeDistributionBlock: { durationDetails: [
  { period: '2026-09-30', duration: 3 }, { period: '2026-09-28', duration: 2 }, { period: '2026-02-30', duration: 999 }
] } }, false, now);
assert.equal(unordered.days[0].key, '2026-09-27');
assert.equal(unordered.totalMinutes, 5);
const year = build({ startTime: new Date(2025, 11, 28).getTime() }, false, now);
assert.equal(year.days[6].key, '2026-01-03');
console.log('PASS: week/month dates, leap year, padding, missing/future days, totals and 60-minute colors');
