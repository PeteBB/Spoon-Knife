/*
 * parser.js — turns a spoken/typed phrase into a calendar event.
 *
 * parse("lunch with Sarah tomorrow at noon for 90 minutes", now)
 *   -> { intent:'create', title:'Lunch with Sarah', date:'2026-08-07',
 *        start:720, duration:90, allDay:false, recurrence:null, ... }
 *
 * Works as a plain browser script (window.VoiceCalParser) and as a CommonJS
 * module (require('./parser.js')) so the same code is unit-tested under Node.
 */
;(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.VoiceCalParser = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  var DAY_ALIASES = {
    sun: 0, sunday: 0, sundays: 0,
    mon: 1, monday: 1, mondays: 1,
    tue: 2, tues: 2, tuesday: 2, tuesdays: 2,
    wed: 3, weds: 3, wednesday: 3, wednesdays: 3,
    thu: 4, thur: 4, thurs: 4, thursday: 4, thursdays: 4,
    fri: 5, friday: 5, fridays: 5,
    sat: 6, saturday: 6, saturdays: 6
  };

  var MONTH_ALIASES = {
    jan: 0, january: 0, feb: 1, february: 1, mar: 2, march: 2, apr: 3, april: 3,
    may: 4, jun: 5, june: 5, jul: 6, july: 6, aug: 7, august: 7,
    sep: 8, sept: 8, september: 8, oct: 9, october: 9, nov: 10, november: 10,
    dec: 11, december: 11
  };

  var NUMBER_WORDS = {
    one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8,
    nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14,
    fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
    twenty: 20, thirty: 30, forty: 40, fourty: 40, fifty: 50, sixty: 60,
    ninety: 90
  };

  var DAY_WORDS = Object.keys(DAY_ALIASES).sort(byLengthDesc).join('|');
  var DAY_PLURALS = 'sundays|mondays|tuesdays|wednesdays|thursdays|fridays|saturdays';
  var MONTH_WORDS = Object.keys(MONTH_ALIASES).sort(byLengthDesc).join('|');
  var NUM_WORDS = Object.keys(NUMBER_WORDS).sort(byLengthDesc).join('|');

  var MARK = ''; // stands in for text we have already consumed

  function byLengthDesc(a, b) { return b.length - a.length; }

  // ---------------------------------------------------------------- helpers

  function pad2(n) { return (n < 10 ? '0' : '') + n; }

  function toKey(d) {
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
  }

  function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }

  function addDays(d, n) {
    var out = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    out.setDate(out.getDate() + n);
    return out;
  }

  function addMonths(d, n) {
    var day = d.getDate();
    var out = new Date(d.getFullYear(), d.getMonth() + n, 1);
    // clamp (Jan 31 + 1 month -> Feb 28/29)
    var lastDay = new Date(out.getFullYear(), out.getMonth() + 1, 0).getDate();
    out.setDate(Math.min(day, lastDay));
    return out;
  }

  /*
   * Bare / "this" weekday  -> the next occurrence, today counts.
   * "next friday"          -> that occurrence, bumped a week when it still
   *                           lands inside the current (Sun-start) week.
   */
  function weekdayFrom(now, dow, modifier) {
    var today = startOfDay(now);
    var delta = (dow - today.getDay() + 7) % 7;
    if (modifier === 'next') {
      if (delta === 0) delta = 7;
      if (today.getDay() + delta < 7) delta += 7;
    }
    return addDays(today, delta);
  }

  function normalize(text) {
    return String(text || '')
      .toLowerCase()
      .replace(/[‘’]/g, "'")
      .replace(/[–—]/g, '-')
      .replace(/\bo'? ?clock\b/g, ' oclock ')
      .replace(/\ba\.m\.?\b/g, 'am')
      .replace(/\bp\.m\.?\b/g, 'pm')
      .replace(/\btmrw?\b/g, 'tomorrow')
      .replace(/[,.;!?]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // "twenty five" -> 25, then number words -> digits, but only next to a
  // time-ish cue so ordinary titles ("Four Seasons kickoff") survive.
  function digitize(text) {
    var out = text.replace(
      new RegExp('\\b(twenty|thirty|forty|fourty|fifty)[ -](one|two|three|four|five|six|seven|eight|nine)\\b', 'g'),
      function (_, tens, ones) { return String(NUMBER_WORDS[tens] + NUMBER_WORDS[ones]); }
    );
    var cueBefore = '(at|for|in|every|each|until|till|past|to|around|about|by|starting)';
    var cueAfter = '(minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|am|pm|oclock|thirty|fifteen|forty five|forty-five)';
    out = out.replace(new RegExp('\\b' + cueBefore + '\\s+(' + NUM_WORDS + ')\\b', 'g'),
      function (_, cue, word) { return cue + ' ' + NUMBER_WORDS[word]; });
    out = out.replace(new RegExp('\\b(' + NUM_WORDS + ')\\s+(?=' + cueAfter + '\\b)', 'g'),
      function (_, word) { return NUMBER_WORDS[word] + ' '; });
    return out;
  }

  function clean(text) {
    return text
      .replace(new RegExp(MARK, 'g'), ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // Recover the original capitalisation of the words left over for the title.
  function restoreCase(remainder, original) {
    var src = original.split(/\s+/);
    var cursor = 0;
    return remainder.split(/\s+/).map(function (word) {
      for (var i = cursor; i < src.length; i++) {
        var bare = src[i].replace(/^[^\w']+|[^\w']+$/g, '');
        if (bare.toLowerCase() === word) { cursor = i + 1; return bare; }
      }
      return word;
    }).join(' ');
  }

  function titleCase(text) {
    if (!text) return '';
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  function meridiemAdjust(hour, meridiem, daypart) {
    if (meridiem === 'am') return hour === 12 ? 0 : hour;
    if (meridiem === 'pm') return hour === 12 ? 12 : hour + 12;
    if (hour === 0 || hour > 12) return hour;              // already 24h
    if (daypart === 'morning') return hour === 12 ? 0 : hour;
    if (daypart === 'afternoon' || daypart === 'evening' || daypart === 'night') {
      return hour === 12 ? 12 : hour + 12;
    }
    // No hint at all: 1-6 reads as afternoon, 7-11 as morning, 12 as noon.
    if (hour >= 1 && hour <= 6) return hour + 12;
    return hour;
  }

  // ----------------------------------------------------------------- parse

  function parse(text, now) {
    now = now ? new Date(now) : new Date();
    var original = String(text || '').trim();
    var work = digitize(normalize(original));

    var result = {
      intent: 'create',
      title: '',
      date: toKey(startOfDay(now)),
      start: null,          // minutes past midnight, null when all-day
      duration: 60,         // minutes
      allDay: true,
      recurrence: null,
      raw: original,
      matched: {},          // which fields the phrase actually specified
      warnings: []
    };

    /*
     * Run `re` against what is left of the phrase. A handler may reject a
     * match by returning false (e.g. "26:09" is not a time), in which case we
     * keep scanning further along the string rather than giving up.
     */
    function consume(re, handler) {
      var scan = new RegExp(re.source, re.flags.indexOf('g') >= 0 ? re.flags : re.flags + 'g');
      var m;
      while ((m = scan.exec(work)) !== null) {
        if (handler(m) !== false) {
          work = work.slice(0, m.index) + MARK + work.slice(m.index + m[0].length);
          return true;
        }
        scan.lastIndex = m.index + 1;
      }
      return false;
    }

    // --- intent + leading command words ---------------------------------
    var del = work.match(/^(?:please\s+)?(?:delete|cancel|remove|drop)\s+(?:my\s+|the\s+|a\s+|an\s+)?/);
    if (del) {
      result.intent = 'delete';
      work = work.slice(del[0].length);
    } else {
      work = work
        .replace(/^(?:hey\s+calendar[\s,]*)?(?:please\s+)?(?:can you\s+|could you\s+)?/, '')
        .replace(/^(?:remind me to|remind me)\s+/, '')
        .replace(/^(?:schedule|add|create|book|set up|setup|make|put in|put|plan|new)\s+(?:a|an|the|my)?\s*/, '');
    }

    var daypart = null;

    // --- recurrence ------------------------------------------------------
    consume(/\bevery\s+(\d+)\s+(day|week|month|year)s?\b/, function (m) {
      result.recurrence = { freq: m[2] + 'ly', interval: parseInt(m[1], 10), byDay: null };
    }) ||
    consume(/\b(?:every|each)\s+other\s+(day|week|month|year)\b/, function (m) {
      result.recurrence = { freq: m[1] + 'ly', interval: 2, byDay: null };
    }) ||
    consume(new RegExp('\\b(?:every|each)\\s+other\\s+(' + DAY_WORDS + ')\\b'), function (m) {
      var dow = DAY_ALIASES[m[1]];
      if (dow === undefined) return false;
      result.recurrence = { freq: 'weekly', interval: 2, byDay: [dow] };
    }) ||
    consume(/\b(?:(?:every|each)\s+(?:week\s?day|weekday)s?|on\s+weekdays|weekdays)\b/, function () {
      result.recurrence = { freq: 'weekly', interval: 1, byDay: [1, 2, 3, 4, 5] };
    }) ||
    consume(/\b(?:(?:every|each)\s+weekends?|on\s+weekends)\b/, function () {
      result.recurrence = { freq: 'weekly', interval: 1, byDay: [0, 6] };
    }) ||
    consume(new RegExp('\\b(?:every|each)\\s+((?:' + DAY_WORDS + ')(?:\\s*(?:and|,|&)\\s*(?:' + DAY_WORDS + '))*)\\b'), function (m) {
      var days = m[1].match(new RegExp('\\b(' + DAY_WORDS + ')\\b', 'g')) || [];
      result.recurrence = {
        freq: 'weekly', interval: 1,
        byDay: days.map(function (d) { return DAY_ALIASES[d]; })
      };
    }) ||
    consume(/\b(?:every|each)\s+(day|morning|afternoon|evening|night)\b/, function () {
      result.recurrence = { freq: 'daily', interval: 1, byDay: null };
    }) ||
    consume(/\b(?:(?:every|each)\s+(week|month|year)|weekly|monthly|yearly|annually)\b/, function (m) {
      var freq = m[1] ? m[1] + 'ly' : (/weekly/.test(m[0]) ? 'weekly' : /monthly/.test(m[0]) ? 'monthly' : 'yearly');
      result.recurrence = { freq: freq, interval: 1, byDay: null };
    }) ||
    consume(/\bdaily\b/, function () {
      result.recurrence = { freq: 'daily', interval: 1, byDay: null };
    }) ||
    consume(new RegExp('\\b(' + DAY_PLURALS + ')\\b'), function (m) {
      // bare plural: "standup mondays"
      var dow = DAY_ALIASES[m[1]];
      if (dow === undefined) return false;
      result.recurrence = { freq: 'weekly', interval: 1, byDay: [dow] };
    });
    if (result.recurrence) result.matched.recurrence = true;

    // --- duration --------------------------------------------------------
    consume(/\bfor\s+(?:an?\s+)?hour\s+and\s+a\s+half\b/, function () {
      result.duration = 90;
    }) ||
    consume(/\bfor\s+half\s+an?\s+hour\b/, function () {
      result.duration = 30;
    }) ||
    consume(/\bfor\s+(?:an?\s+)?(?:(\d+(?:\.\d+)?)\s*)?(hours?|hrs?|h|minutes?|mins?|m)\b/, function (m) {
      var qty = m[1] ? parseFloat(m[1]) : 1;
      result.duration = /^(h|hr|hrs|hour|hours)$/.test(m[2]) ? Math.round(qty * 60) : Math.round(qty);
    }) ||
    consume(/\b(\d+(?:\.\d+)?)[- ]?(hours?|hrs?|minutes?|mins?)\s+(?:long\b|(?=\w))/, function (m) {
      // "30 minute call", "2 hour workshop"
      var qty = parseFloat(m[1]);
      result.duration = /^(hrs?|hours?)$/.test(m[2]) ? Math.round(qty * 60) : Math.round(qty);
    });
    if (result.duration !== 60) result.matched.duration = true;

    // --- daypart hints ---------------------------------------------------
    consume(/\b(?:in\s+the\s+)?(morning|afternoon|evening)\b/, function (m) {
      daypart = m[1];
    });
    if (!daypart) {
      consume(/\b(tonight|at\s+night)\b/, function () { daypart = 'evening'; });
    }

    // --- numeric dates ---------------------------------------------------
    // Parsed before times so "2026-09-01 at 8am" and "12/25 at 9am" cannot be
    // mistaken for clock digits.
    var todayStart = startOfDay(now);
    consume(/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/, function (m) {
      if (+m[2] > 12 || +m[3] > 31) return false;
      result.date = toKey(new Date(+m[1], +m[2] - 1, +m[3]));
      result.matched.date = true;
    }) ||
    consume(/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/, function (m) {
      if (+m[1] > 12 || +m[2] > 31) return false;
      var year = m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : todayStart.getFullYear();
      var d = new Date(year, +m[1] - 1, +m[2]);
      if (!m[3] && d < todayStart) d = new Date(year + 1, +m[1] - 1, +m[2]);
      result.date = toKey(d);
      result.matched.date = true;
    });

    // --- explicit times --------------------------------------------------
    var startMin = null, endMin = null;

    function hm(hour, minute, meridiem) {
      return meridiemAdjust(hour, meridiem, daypart) * 60 + minute;
    }

    // "in 20 minutes" / "in 2 hours" -> relative to now
    var relative = false;
    consume(/\bin\s+(\d+(?:\.\d+)?)\s*(minutes?|mins?|hours?|hrs?)\b/, function (m) {
      var qty = parseFloat(m[1]);
      var offset = /^(hrs?|hours?)$/.test(m[2]) ? qty * 60 : qty;
      var at = new Date(now.getTime() + offset * 60000);
      at.setSeconds(0, 0);
      startMin = at.getHours() * 60 + at.getMinutes();
      result.date = toKey(at);
      result.matched.date = true;
      relative = true;
    });

    // clock idioms: "half past three", "quarter to four", "ten past nine"
    if (!relative) {
      // "half/quarter to" only — a bare "2 to 4" is a range, not 3:58.
      consume(/\b(half|quarter|\d{1,2})\s+(past|after|to|till|before)\s+(\d{1,2}|noon|midnight)\s*(am|pm)?\b/, function (m) {
        var offset = m[1] === 'half' ? 30 : m[1] === 'quarter' ? 15 : parseInt(m[1], 10);
        if (offset > 59) return false;
        if (/^(to|till|before)$/.test(m[2]) && !/^(half|quarter)$/.test(m[1])) return false;
        var anchorWord = m[3];
        var anchor = anchorWord === 'noon' ? 12 : anchorWord === 'midnight' ? 0 : parseInt(anchorWord, 10);
        if (anchor > 24) return false;
        var forward = /^(past|after)$/.test(m[2]);
        var base = anchorWord === 'noon' || anchorWord === 'midnight'
          ? (anchorWord === 'noon' ? 12 * 60 : 0)
          : hm(anchor, 0, m[4]);
        startMin = forward ? base + offset : base - offset;
        if (startMin < 0) startMin += 24 * 60;
      });
    }

    // ranges: "from 2 to 4", "2-3:30pm", "between 9 and 10am"
    if (startMin === null) {
      consume(/\b(?:from\s+|between\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|till|and)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/, function (m) {
        var h1 = parseInt(m[1], 10), m1 = m[2] ? parseInt(m[2], 10) : 0, mer1 = m[3];
        var h2 = parseInt(m[4], 10), m2 = m[5] ? parseInt(m[5], 10) : 0, mer2 = m[6];
        if (h1 > 24 || h2 > 24 || m1 > 59 || m2 > 59) return false;
        // "2 to 4pm" -> both pm; "9am to 5" -> both am unless it wraps
        if (!mer1 && mer2) mer1 = (h1 <= h2 || (h1 > 12)) ? mer2 : mer1;
        endMin = hm(h2, m2, mer2);
        startMin = hm(h1, m1, mer1);
        if (endMin <= startMin) endMin += 12 * 60;         // "9 to 5"
        if (endMin <= startMin) endMin += 12 * 60;
      });
    }

    if (startMin === null) {
      consume(/\b(?:at\s+|@\s*)?(\d{1,2}):(\d{2})\s*(am|pm)?\b/, function (m) {
        var h = parseInt(m[1], 10), mm = parseInt(m[2], 10);
        if (h > 24 || mm > 59) return false;
        startMin = hm(h, mm, m[3]);
      }) ||
      consume(/\b(?:at\s+|@\s*)?(\d{1,2})\s*(am|pm)\b/, function (m) {
        var h = parseInt(m[1], 10);
        if (h > 24) return false;
        startMin = hm(h, 0, m[2]);
      }) ||
      consume(/\b(?:at|@)\s+(\d{1,2})\s+(\d{2})\b/, function (m) {
        // "at 3 30" — speech engines often drop the colon
        var h = parseInt(m[1], 10), mm = parseInt(m[2], 10);
        if (h > 24 || mm > 59) return false;
        startMin = hm(h, mm, null);
      }) ||
      consume(/\b(?:at|@)\s+(\d{1,2})\s*(?:oclock)?\b/, function (m) {
        var h = parseInt(m[1], 10);
        if (h > 24) return false;
        startMin = hm(h, 0, null);
      }) ||
      consume(/\b(noon|midday|midnight)\b/, function (m) {
        startMin = m[1] === 'midnight' ? 0 : 12 * 60;
      });
    }

    work = work.replace(/\boclock\b/g, ' ');

    if (startMin !== null) {
      result.start = ((startMin % 1440) + 1440) % 1440;
      result.allDay = false;
      result.matched.time = true;
      if (endMin !== null && endMin > startMin) {
        result.duration = endMin - startMin;
        result.matched.duration = true;
      }
    } else if (daypart) {
      result.start = daypart === 'morning' ? 9 * 60 : daypart === 'afternoon' ? 14 * 60 : 19 * 60;
      result.allDay = false;
      result.matched.time = true;
    }

    // --- date ------------------------------------------------------------
    if (!result.matched.date) {
      var today = startOfDay(now);

      consume(/\bday after tomorrow\b/, function () {
        result.date = toKey(addDays(today, 2));
        result.matched.date = true;
      }) ||
      consume(/\b(today|tonight)\b/, function () {
        result.date = toKey(today);
        result.matched.date = true;
      }) ||
      consume(/\btomorrow\b/, function () {
        result.date = toKey(addDays(today, 1));
        result.matched.date = true;
      }) ||
      consume(/\byesterday\b/, function () {
        result.date = toKey(addDays(today, -1));
        result.matched.date = true;
      }) ||
      consume(/\bin\s+(\d+)\s+(days?|weeks?|months?|years?)\b/, function (m) {
        var n = parseInt(m[1], 10);
        var d = /^day/.test(m[2]) ? addDays(today, n)
          : /^week/.test(m[2]) ? addDays(today, n * 7)
          : /^month/.test(m[2]) ? addMonths(today, n)
          : addMonths(today, n * 12);
        result.date = toKey(d);
        result.matched.date = true;
      }) ||
      consume(new RegExp('\\b(?:on\\s+)?(this|next|coming)?\\s*(' + MONTH_WORDS + ')\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+(\\d{4}))?\\b'), function (m) {
        var month = MONTH_ALIASES[m[2]], day = parseInt(m[3], 10);
        if (day > 31) return false;
        var year = m[4] ? +m[4] : today.getFullYear();
        var d = new Date(year, month, day);
        if (!m[4] && d < today) d = new Date(year + 1, month, day);
        result.date = toKey(d);
        result.matched.date = true;
      }) ||
      consume(new RegExp('\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(' + MONTH_WORDS + ')(?:\\s+(\\d{4}))?\\b'), function (m) {
        var day = parseInt(m[1], 10), month = MONTH_ALIASES[m[2]];
        if (day > 31) return false;
        var year = m[3] ? +m[3] : today.getFullYear();
        var d = new Date(year, month, day);
        if (!m[3] && d < today) d = new Date(year + 1, month, day);
        result.date = toKey(d);
        result.matched.date = true;
      }) ||
      consume(new RegExp('\\b(this|next|coming)?\\s*(?:on\\s+)?(' + DAY_WORDS + ')\\b'), function (m) {
        var dow = DAY_ALIASES[m[2]];
        if (dow === undefined) return false;
        result.date = toKey(weekdayFrom(now, dow, m[1] === 'next' ? 'next' : null));
        result.matched.date = true;
      }) ||
      consume(/\bnext\s+(week|month|year)\b/, function (m) {
        var d = m[1] === 'week' ? addDays(today, 7) : m[1] === 'month' ? addMonths(today, 1) : addMonths(today, 12);
        result.date = toKey(d);
        result.matched.date = true;
      }) ||
      consume(/\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b/, function (m) {
        var day = parseInt(m[1], 10);
        if (day > 31) return false;
        var d = new Date(today.getFullYear(), today.getMonth(), day);
        if (d < today) d = addMonths(new Date(today.getFullYear(), today.getMonth(), day), 1);
        result.date = toKey(d);
        result.matched.date = true;
      }) ||
      consume(/\b(?:this\s+)?weekend\b/, function () {
        result.date = toKey(weekdayFrom(now, 6, null));
        result.matched.date = true;
      });
    }

    // Recurring with named days but no start date: begin on the first match.
    if (result.recurrence && result.recurrence.byDay && !result.matched.date) {
      var candidates = result.recurrence.byDay.map(function (dow) {
        return weekdayFrom(now, dow, null);
      }).sort(function (a, b) { return a - b; });
      result.date = toKey(candidates[0]);
    }

    // A time that has already gone by today, with no date said, means tomorrow.
    if (!result.matched.date && !result.recurrence && result.start !== null) {
      var nowMin = now.getHours() * 60 + now.getMinutes();
      if (result.start <= nowMin) result.date = toKey(addDays(startOfDay(now), 1));
    }

    // --- title -----------------------------------------------------------
    var leftover = clean(work)
      .replace(/\b(?:starting|beginning|start|starts|on|at|in|from|of|the|a|an|my|is|it|to)\b\s*$/g, '')
      .replace(/^\s*(?:on|at|in|for|of|the|a|an|and|to)\b\s*/g, '')
      .replace(/\s+/g, ' ')
      .trim();

    result.title = titleCase(restoreCase(leftover, original));
    if (!result.title && result.intent === 'create') {
      result.warnings.push('no-title');
    }
    if (!result.matched.time && result.intent === 'create') {
      result.warnings.push('no-time');
    }
    return result;
  }

  return {
    parse: parse,
    toKey: toKey,
    startOfDay: startOfDay,
    addDays: addDays,
    addMonths: addMonths,
    weekdayFrom: weekdayFrom,
    DAY_ALIASES: DAY_ALIASES,
    MONTH_ALIASES: MONTH_ALIASES
  };
});
