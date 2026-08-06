/*
 * Plain-node test suite for the phrase parser: `node calendar/test/parser.test.js`
 * No dependencies, no test framework.
 */
'use strict';

var parser = require('../parser.js');

// Reference "now": Thursday 6 August 2026, 15:00 local time.
var NOW = new Date(2026, 7, 6, 15, 0, 0);

var passed = 0;
var failures = [];

function check(phrase, expected, now) {
  var got = parser.parse(phrase, now || NOW);
  var bad = [];
  Object.keys(expected).forEach(function (key) {
    var want = expected[key];
    var have = got[key];
    var same = (typeof want === 'object' && want !== null)
      ? JSON.stringify(sortRecurrence(have)) === JSON.stringify(sortRecurrence(want))
      : have === want;
    if (!same) bad.push('  ' + key + ': expected ' + JSON.stringify(want) + ', got ' + JSON.stringify(have));
  });
  if (bad.length) failures.push('"' + phrase + '"\n' + bad.join('\n'));
  else passed++;
}

function sortRecurrence(r) {
  if (!r || typeof r !== 'object') return r;
  return { freq: r.freq, interval: r.interval, byDay: r.byDay ? r.byDay.slice().sort() : null };
}

function hhmm(h, m) { return h * 60 + (m || 0); }

/* -------------------------------------------------------------- titles */
check('lunch with Sarah tomorrow at noon', { title: 'Lunch with Sarah', date: '2026-08-07', start: hhmm(12), allDay: false });
check('schedule a dentist appointment on March 3rd at 2:30pm', { title: 'Dentist appointment', date: '2027-03-03', start: hhmm(14, 30) });
check('remind me to call mom tomorrow at 6pm', { title: 'Call mom', date: '2026-08-07', start: hhmm(18) });
check('add coffee with Dave friday at 9am', { title: 'Coffee with Dave', date: '2026-08-07', start: hhmm(9) });
check('book a meeting with the design team next tuesday at 11', { title: 'Meeting with the design team', date: '2026-08-11', start: hhmm(11) });
check('Four Seasons site visit on the 12th at 10am', { title: 'Four Seasons site visit', date: '2026-08-12', start: hhmm(10) });

/* ---------------------------------------------------------------- dates */
check('standup today at 9:15am', { date: '2026-08-06', start: hhmm(9, 15) });
check('flight day after tomorrow at 7am', { date: '2026-08-08', start: hhmm(7) });
check('review in 3 days at 4pm', { date: '2026-08-09', start: hhmm(16) });
check('planning in 2 weeks at 10am', { date: '2026-08-20', start: hhmm(10) });
check('board meeting on 12/25 at 9am', { date: '2026-12-25', start: hhmm(9) });
check('kickoff 2026-09-01 at 8am', { date: '2026-09-01', start: hhmm(8) });
check('party on the 3rd of october at 8pm', { date: '2026-10-03', start: hhmm(20) });
check('checkup on september 9 at 1pm', { date: '2026-09-09', start: hhmm(13) });
check('haircut on the 2nd at 5pm', { date: '2026-09-02', start: hhmm(17) });   // 2nd already passed this month
check('drinks thursday at 7pm', { date: '2026-08-06', start: hhmm(19) });       // today is Thursday
check('drinks next thursday at 7pm', { date: '2026-08-13', start: hhmm(19) });
check('brunch this weekend at 11am', { date: '2026-08-08', start: hhmm(11) });
check('offsite next week', { date: '2026-08-13', allDay: true });
check('yoga at 7am', { date: '2026-08-07', start: hhmm(7) });                   // 7am already gone -> tomorrow
check('yoga at 7pm', { date: '2026-08-06', start: hhmm(19) });

/* ---------------------------------------------------------------- times */
check('call at 3', { start: hhmm(15) });                                        // 1-6 reads as pm
check('call at 10', { start: hhmm(10) });
check('call at 8 in the morning', { start: hhmm(8) });
check('call at 8 in the evening', { start: hhmm(20) });
check('dinner tonight', { start: hhmm(19), allDay: false, date: '2026-08-06' });
check('standup at 9 30 tomorrow', { start: hhmm(9, 30) });
check('sync at 14:45 tomorrow', { start: hhmm(14, 45) });
check('lunch at midday tomorrow', { start: hhmm(12) });
check('alarm at midnight', { start: 0 });
check('tea at half past three tomorrow', { start: hhmm(15, 30) });
check('tea at quarter to four tomorrow', { start: hhmm(15, 45) });
check('meeting in 30 minutes', { start: hhmm(15, 30), date: '2026-08-06' });

/* ------------------------------------------------------------- durations */
check('lunch with Sarah tomorrow at noon for 90 minutes', { start: hhmm(12), duration: 90 });
check('gym tomorrow at 6am for an hour', { start: hhmm(6), duration: 60 });
check('call tomorrow at 2pm for half an hour', { start: hhmm(14), duration: 30 });
check('workshop tomorrow at 9am for 2 hours', { start: hhmm(9), duration: 120 });
check('deep work tomorrow at 9am for an hour and a half', { duration: 90 });
check('30 minute call with Ann tomorrow at 4pm', { title: 'Call with Ann', duration: 30, start: hhmm(16) });
check('workshop tomorrow from 2 to 4', { start: hhmm(14), duration: 120 });
check('shift tomorrow from 9am to 5pm', { start: hhmm(9), duration: 480 });
check('meeting tomorrow between 10 and 11am', { start: hhmm(10), duration: 60 });

/* ------------------------------------------------------------ recurrence */
check('standup every weekday at 9am', {
  title: 'Standup', start: hhmm(9),
  recurrence: { freq: 'weekly', interval: 1, byDay: [1, 2, 3, 4, 5] }
});
check('gym every monday and wednesday at 7am', {
  title: 'Gym', start: hhmm(7),
  recurrence: { freq: 'weekly', interval: 1, byDay: [1, 3] },
  date: '2026-08-10'
});
check('take pills every day at 8am', {
  title: 'Take pills', recurrence: { freq: 'daily', interval: 1, byDay: null }
});
check('payroll every month on the 1st', {
  recurrence: { freq: 'monthly', interval: 1, byDay: null }, date: '2026-09-01'
});
check('retro every 2 weeks on friday at 3pm', {
  recurrence: { freq: 'weekly', interval: 2, byDay: null }, date: '2026-08-07', start: hhmm(15)
});
check('sprint review every other tuesday at 10am', {
  recurrence: { freq: 'weekly', interval: 2, byDay: [2] }, date: '2026-08-11', start: hhmm(10)
});

/* ---------------------------------------------------------------- delete */
check('cancel my dentist appointment', { intent: 'delete', title: 'Dentist appointment' });
check('delete standup tomorrow', { intent: 'delete', title: 'Standup', date: '2026-08-07' });

/* ------------------------------------------------------------- all-day */
check('holiday on friday', { allDay: true, start: null, date: '2026-08-07' });
check('Ellies birthday on september 9', { allDay: true, date: '2026-09-09' });

/* ----------------------------------------------------------------- report */
console.log('passed: ' + passed + '   failed: ' + failures.length);
if (failures.length) {
  console.log('\n' + failures.join('\n\n'));
  process.exit(1);
}
