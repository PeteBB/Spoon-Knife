/*
 * app.js — the calendar UI: month grid, day agenda, dictation, editing,
 * recurrence expansion, localStorage persistence and .ics export.
 */
(function () {
  'use strict';

  var P = window.VoiceCalParser;
  var STORE_KEY = 'voicecal.v1';
  var MAX_CHIPS = 3;

  var EXAMPLES = [
    'Lunch with Sarah tomorrow at noon for 90 minutes',
    'Dentist next Thursday at 2:30pm',
    'Standup every weekday at 9:15am for 15 minutes',
    'Gym every Monday and Wednesday at 7am',
    'Design review Friday from 2 to 4',
    'Mum’s birthday on 12 September'
  ];

  var state = {
    events: [],
    settings: { speak: true, handsFree: false },
    view: null,        // Date pinned to the 1st of the displayed month
    selected: null     // 'YYYY-MM-DD'
  };

  var $ = function (id) { return document.getElementById(id); };

  // ------------------------------------------------------------- storage

  function load() {
    try {
      var raw = JSON.parse(localStorage.getItem(STORE_KEY) || '{}');
      if (Array.isArray(raw.events)) state.events = raw.events.filter(validEvent);
      if (raw.settings) {
        state.settings.speak = raw.settings.speak !== false;
        state.settings.handsFree = !!raw.settings.handsFree;
      }
    } catch (err) {
      console.warn('Could not read saved events:', err);
    }
  }

  function save() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify({
        events: state.events,
        settings: state.settings
      }));
    } catch (err) {
      toast('Saving failed — storage may be full or blocked.', null, null);
    }
  }

  function validEvent(ev) {
    return ev && typeof ev.id === 'string' && typeof ev.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(ev.date);
  }

  function uid() {
    return 'e' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  }

  // --------------------------------------------------------------- dates

  function keyToDate(key) {
    var p = key.split('-');
    return new Date(+p[0], +p[1] - 1, +p[2]);
  }

  function daysBetween(a, b) {
    return Math.round((b - a) / 86400000);
  }

  function weekStart(d) {
    return P.addDays(d, -d.getDay());
  }

  function todayKey() {
    return P.toKey(new Date());
  }

  function fmtTime(minutes) {
    var d = new Date(2000, 0, 1, Math.floor(minutes / 60), minutes % 60);
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }

  function fmtRange(ev) {
    if (ev.allDay || ev.start === null) return 'All day';
    var end = ev.start + (ev.duration || 60);
    return fmtTime(ev.start) + ' – ' + fmtTime(end % 1440);
  }

  function fmtDuration(min) {
    if (min % 60 === 0) return (min / 60) + (min === 60 ? ' hour' : ' hours');
    if (min < 60) return min + ' min';
    return Math.floor(min / 60) + 'h ' + (min % 60) + 'm';
  }

  function fmtDayLong(key) {
    return keyToDate(key).toLocaleDateString([], {
      weekday: 'long', month: 'long', day: 'numeric'
    });
  }

  // ---------------------------------------------------------- recurrence

  function describeRecurrence(r) {
    if (!r) return '';
    var every = r.interval > 1 ? 'Every ' + r.interval + ' ' : 'Every ';
    var names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    if (r.freq === 'daily') return r.interval > 1 ? every + 'days' : 'Every day';
    if (r.freq === 'weekly') {
      if (r.byDay && r.byDay.length === 5 && r.byDay.indexOf(0) < 0 && r.byDay.indexOf(6) < 0) return 'Every weekday';
      if (r.byDay && r.byDay.length) {
        return every.trim() + ' ' + r.byDay.map(function (d) { return names[d]; }).join(', ');
      }
      return r.interval > 1 ? every + 'weeks' : 'Every week';
    }
    if (r.freq === 'monthly') return r.interval > 1 ? every + 'months' : 'Every month';
    if (r.freq === 'yearly') return r.interval > 1 ? every + 'years' : 'Every year';
    return 'Repeats';
  }

  /* Every date this event lands on inside [from, to] (both midnight Dates). */
  function occurrencesInRange(ev, from, to) {
    var list = [];
    var start = keyToDate(ev.date);
    var r = ev.recurrence;
    var end = to;
    if (r && r.until) {
      var until = keyToDate(r.until);
      if (until < end) end = until;
    }
    if (start > end) return list;

    if (!r) {
      if (start >= from && start <= end) list.push(ev.date);
      return list;
    }

    var interval = Math.max(1, r.interval || 1);
    var i, d;

    if (r.freq === 'daily') {
      var first = start;
      if (first < from) {
        first = P.addDays(start, Math.ceil(daysBetween(start, from) / interval) * interval);
      }
      for (d = first; d <= end; d = P.addDays(d, interval)) list.push(P.toKey(d));

    } else if (r.freq === 'weekly') {
      var days = (r.byDay && r.byDay.length) ? r.byDay : [start.getDay()];
      var anchor = weekStart(start);
      var scan = weekStart(from < start ? start : from);
      var off = Math.round(daysBetween(anchor, scan) / 7) % interval;
      if (off !== 0) scan = P.addDays(scan, (interval - off) * 7);
      for (var w = scan; w <= end; w = P.addDays(w, interval * 7)) {
        for (i = 0; i < days.length; i++) {
          d = P.addDays(w, days[i]);
          if (d >= start && d >= from && d <= end) list.push(P.toKey(d));
        }
      }

    } else if (r.freq === 'monthly') {
      var dom = start.getDate();
      var cur = new Date(start.getFullYear(), start.getMonth(), 1);
      var fromMonth = new Date(from.getFullYear(), from.getMonth(), 1);
      if (cur < fromMonth) {
        var monthsOff = (from.getFullYear() - start.getFullYear()) * 12 + (from.getMonth() - start.getMonth());
        cur = new Date(start.getFullYear(), start.getMonth() + Math.floor(monthsOff / interval) * interval, 1);
      }
      for (; cur <= end; cur = new Date(cur.getFullYear(), cur.getMonth() + interval, 1)) {
        var lastDay = new Date(cur.getFullYear(), cur.getMonth() + 1, 0).getDate();
        if (dom > lastDay) continue;                       // skip short months
        d = new Date(cur.getFullYear(), cur.getMonth(), dom);
        if (d >= start && d >= from && d <= end) list.push(P.toKey(d));
      }

    } else if (r.freq === 'yearly') {
      var y0 = start.getFullYear();
      var yStart = Math.max(y0, y0 + Math.floor((from.getFullYear() - y0) / interval) * interval);
      for (var y = yStart; y <= end.getFullYear(); y += interval) {
        d = new Date(y, start.getMonth(), start.getDate());
        if (d >= start && d >= from && d <= end) list.push(P.toKey(d));
      }
    }

    var ex = ev.exceptions || [];
    return list.filter(function (k) { return ex.indexOf(k) < 0; });
  }

  /* { 'YYYY-MM-DD': [event, …] } for the visible range, each list sorted. */
  function occurrenceMap(from, to) {
    var map = {};
    state.events.forEach(function (ev) {
      occurrencesInRange(ev, from, to).forEach(function (key) {
        (map[key] || (map[key] = [])).push(ev);
      });
    });
    Object.keys(map).forEach(function (key) {
      map[key].sort(function (a, b) {
        var as = a.allDay ? -1 : a.start;
        var bs = b.allDay ? -1 : b.start;
        return as - bs || a.title.localeCompare(b.title);
      });
    });
    return map;
  }

  function hueOf(ev) {
    var h = 0;
    var s = ev.title || ev.id;
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
    return h;
  }

  // ------------------------------------------------------------ rendering

  function renderWeekdayHeader() {
    var row = $('weekdays');
    row.innerHTML = '';
    var base = weekStart(new Date());
    for (var i = 0; i < 7; i++) {
      var cell = document.createElement('div');
      cell.textContent = P.addDays(base, i).toLocaleDateString([], { weekday: 'short' });
      row.appendChild(cell);
    }
  }

  function render() {
    renderMonth();
    renderAgenda();
  }

  function renderMonth() {
    var first = state.view;
    $('monthLabel').textContent = first.toLocaleDateString([], { month: 'long', year: 'numeric' });

    var gridStart = P.addDays(first, -first.getDay());
    var gridEnd = P.addDays(gridStart, 41);
    var map = occurrenceMap(gridStart, gridEnd);
    var today = todayKey();

    var grid = $('grid');
    var frag = document.createDocumentFragment();

    for (var i = 0; i < 42; i++) {
      var day = P.addDays(gridStart, i);
      var key = P.toKey(day);
      var cell = document.createElement('div');
      cell.className = 'cell';
      cell.dataset.date = key;
      cell.tabIndex = 0;
      cell.setAttribute('role', 'button');
      cell.setAttribute('aria-label', fmtDayLong(key));
      if (day.getMonth() !== first.getMonth()) cell.classList.add('other-month');
      if (key === today) cell.classList.add('today');
      if (key === state.selected) cell.classList.add('selected');

      var num = document.createElement('div');
      num.className = 'daynum';
      num.textContent = day.getDate();
      cell.appendChild(num);

      var items = map[key] || [];
      items.slice(0, MAX_CHIPS).forEach(function (ev) {
        cell.appendChild(chip(ev, key));
      });
      if (items.length > MAX_CHIPS) {
        var more = document.createElement('div');
        more.className = 'more';
        more.textContent = '+' + (items.length - MAX_CHIPS) + ' more';
        cell.appendChild(more);
      }
      frag.appendChild(cell);
    }

    grid.innerHTML = '';
    grid.appendChild(frag);
  }

  function chip(ev, dateKey) {
    var el = document.createElement('button');
    el.type = 'button';
    el.className = 'chip' + (ev.allDay ? ' allday' : '');
    el.style.setProperty('--hue', hueOf(ev));
    el.dataset.id = ev.id;
    el.dataset.date = dateKey;
    el.title = ev.title + ' · ' + fmtRange(ev) + (ev.recurrence ? ' · ' + describeRecurrence(ev.recurrence) : '');
    if (!ev.allDay && ev.start !== null) {
      var t = document.createElement('span');
      t.className = 'chip-time';
      t.textContent = fmtTime(ev.start);
      el.appendChild(t);
    }
    var label = document.createElement('span');
    label.className = 'chip-title';
    label.textContent = ev.title;
    el.appendChild(label);
    return el;
  }

  function renderAgenda() {
    var key = state.selected;
    var isToday = key === todayKey();
    $('agendaTitle').textContent = (isToday ? 'Today · ' : '') + fmtDayLong(key);

    var day = keyToDate(key);
    var items = occurrenceMap(day, day)[key] || [];
    var list = $('agendaList');
    list.innerHTML = '';

    if (!items.length) {
      var empty = document.createElement('li');
      empty.className = 'empty';
      empty.textContent = 'Nothing scheduled. Press the mic and say what you need.';
      list.appendChild(empty);
      return;
    }

    items.forEach(function (ev) {
      var li = document.createElement('li');
      li.className = 'agenda-item';
      li.style.setProperty('--hue', hueOf(ev));

      var when = document.createElement('div');
      when.className = 'when';
      when.textContent = ev.allDay ? 'All day' : fmtTime(ev.start);
      li.appendChild(when);

      var body = document.createElement('div');
      body.className = 'body';

      var h = document.createElement('div');
      h.className = 'title';
      h.textContent = ev.title;
      body.appendChild(h);

      var meta = document.createElement('div');
      meta.className = 'meta';
      var bits = [];
      if (!ev.allDay) bits.push(fmtRange(ev) + ' · ' + fmtDuration(ev.duration || 60));
      if (ev.recurrence) bits.push('↻ ' + describeRecurrence(ev.recurrence));
      meta.textContent = bits.join('  ·  ');
      body.appendChild(meta);

      if (ev.notes) {
        var notes = document.createElement('div');
        notes.className = 'notes';
        notes.textContent = ev.notes;
        body.appendChild(notes);
      }
      li.appendChild(body);

      var actions = document.createElement('div');
      actions.className = 'row-actions';
      actions.appendChild(rowBtn('Edit', 'Edit ' + ev.title, function () { openEditor(ev, key); }));
      actions.appendChild(rowBtn('Delete', 'Delete ' + ev.title, function () { requestDelete(ev, key); }));
      li.appendChild(actions);

      list.appendChild(li);
    });
  }

  function rowBtn(label, aria, onClick) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'link-btn';
    b.textContent = label;
    b.setAttribute('aria-label', aria);
    b.addEventListener('click', onClick);
    return b;
  }

  // --------------------------------------------------------------- toast

  var toastTimer = null;

  function toast(text, actionLabel, onAction) {
    var box = $('toast');
    var btn = $('toastAction');
    $('toastText').textContent = text;
    if (actionLabel) {
      btn.textContent = actionLabel;
      btn.hidden = false;
      btn.onclick = function () { hideToast(); onAction(); };
    } else {
      btn.hidden = true;
      btn.onclick = null;
    }
    box.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 7000);
  }

  function hideToast() {
    $('toast').hidden = true;
    clearTimeout(toastTimer);
  }

  // ------------------------------------------------------- event actions

  function addEvent(ev, opts) {
    state.events.push(ev);
    save();
    state.selected = ev.date;
    state.view = new Date(keyToDate(ev.date).getFullYear(), keyToDate(ev.date).getMonth(), 1);
    render();
    var summary = describe(ev);
    if (!opts || opts.announce !== false) {
      toast('Added ' + summary, 'Undo', function () { removeEvent(ev.id); });
      say('Added ' + summary);
    }
  }

  function removeEvent(id) {
    state.events = state.events.filter(function (e) { return e.id !== id; });
    save();
    render();
  }

  function describe(ev) {
    var bits = [ev.title];
    if (ev.recurrence) bits.push(describeRecurrence(ev.recurrence).toLowerCase());
    else bits.push(relativeDay(ev.date));
    if (!ev.allDay && ev.start !== null) bits.push('at ' + fmtTime(ev.start));
    return bits.join(', ');
  }

  function relativeDay(key) {
    var diff = daysBetween(keyToDate(todayKey()), keyToDate(key));
    if (diff === 0) return 'today';
    if (diff === 1) return 'tomorrow';
    if (diff === -1) return 'yesterday';
    if (diff > 1 && diff < 7) return 'on ' + keyToDate(key).toLocaleDateString([], { weekday: 'long' });
    return 'on ' + keyToDate(key).toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
  }

  function requestDelete(ev, dateKey) {
    if (!ev.recurrence) {
      var copy = JSON.parse(JSON.stringify(ev));
      removeEvent(ev.id);
      toast('Deleted “' + ev.title + '”', 'Undo', function () {
        state.events.push(copy);
        save();
        render();
      });
      return;
    }
    askScope(ev, dateKey);
  }

  function askScope(ev, dateKey) {
    var dlg = $('scopeDialog');
    $('scopeText').textContent = '“' + ev.title + '” ' + describeRecurrence(ev.recurrence).toLowerCase() +
      '. Delete just ' + fmtDayLong(dateKey) + ', or the whole series?';

    $('scopeOne').onclick = function () {
      dlg.close();
      ev.exceptions = (ev.exceptions || []).concat([dateKey]);
      save();
      render();
      toast('Removed “' + ev.title + '” on ' + fmtDayLong(dateKey), 'Undo', function () {
        ev.exceptions = ev.exceptions.filter(function (k) { return k !== dateKey; });
        save();
        render();
      });
    };
    $('scopeAll').onclick = function () {
      dlg.close();
      var copy = JSON.parse(JSON.stringify(ev));
      removeEvent(ev.id);
      toast('Deleted the “' + ev.title + '” series', 'Undo', function () {
        state.events.push(copy);
        save();
        render();
      });
    };
    $('scopeCancel').onclick = function () { dlg.close(); };
    dlg.showModal();
  }

  /* "cancel my dentist appointment" — drop the soonest title match. */
  function deleteByPhrase(parsed) {
    var needle = (parsed.title || '').toLowerCase().trim();
    if (!needle) {
      toast('I didn’t catch which event to remove.', null, null);
      return;
    }
    var from = parsed.matched.date ? keyToDate(parsed.date) : keyToDate(todayKey());
    var to = parsed.matched.date ? from : P.addDays(from, 365);
    var hits = [];
    state.events.forEach(function (ev) {
      if (ev.title.toLowerCase().indexOf(needle) < 0) return;
      occurrencesInRange(ev, from, to).forEach(function (key) { hits.push({ ev: ev, key: key }); });
    });
    if (!hits.length) {
      toast('No upcoming event matching “' + parsed.title + '”.', null, null);
      say('I could not find ' + parsed.title);
      return;
    }
    hits.sort(function (a, b) { return a.key < b.key ? -1 : 1; });
    var hit = hits[0];
    state.selected = hit.key;
    state.view = new Date(keyToDate(hit.key).getFullYear(), keyToDate(hit.key).getMonth(), 1);
    render();
    say('Removing ' + hit.ev.title);
    requestDelete(hit.ev, hit.key);
  }

  // -------------------------------------------------------------- editor

  var editing = null;   // { event, isNew, dateKey }

  function blankEvent(dateKey) {
    return {
      id: uid(), title: '', date: dateKey || state.selected, allDay: false,
      start: 9 * 60, duration: 60, notes: '', recurrence: null, exceptions: []
    };
  }

  function eventFromParsed(p) {
    return {
      id: uid(),
      title: p.title,
      date: p.date,
      allDay: p.allDay,
      start: p.start,
      duration: p.duration,
      notes: '',
      recurrence: p.recurrence ? {
        freq: p.recurrence.freq,
        interval: p.recurrence.interval || 1,
        byDay: p.recurrence.byDay || null,
        until: null
      } : null,
      exceptions: []
    };
  }

  function repeatValue(r) {
    if (!r) return '';
    if (r.freq === 'daily' && r.interval === 1) return 'daily';
    if (r.freq === 'weekly' && r.interval === 1 && r.byDay && r.byDay.length === 5 &&
        r.byDay.indexOf(0) < 0 && r.byDay.indexOf(6) < 0) return 'weekdays';
    if (r.freq === 'weekly' && r.interval === 1 && (!r.byDay || r.byDay.length === 1)) return 'weekly';
    if (r.freq === 'weekly' && r.interval === 2 && (!r.byDay || r.byDay.length === 1)) return 'biweekly';
    if (r.freq === 'monthly' && r.interval === 1) return 'monthly';
    if (r.freq === 'yearly' && r.interval === 1) return 'yearly';
    return '__custom';
  }

  function repeatFromValue(value, dateKey, previous) {
    switch (value) {
      case 'daily': return { freq: 'daily', interval: 1, byDay: null, until: null };
      case 'weekdays': return { freq: 'weekly', interval: 1, byDay: [1, 2, 3, 4, 5], until: null };
      case 'weekly': return { freq: 'weekly', interval: 1, byDay: [keyToDate(dateKey).getDay()], until: null };
      case 'biweekly': return { freq: 'weekly', interval: 2, byDay: [keyToDate(dateKey).getDay()], until: null };
      case 'monthly': return { freq: 'monthly', interval: 1, byDay: null, until: null };
      case 'yearly': return { freq: 'yearly', interval: 1, byDay: null, until: null };
      case '__custom': return previous || null;
      default: return null;
    }
  }

  function openEditor(ev, dateKey, opts) {
    var isNew = state.events.indexOf(ev) < 0;
    editing = { event: ev, isNew: isNew, dateKey: dateKey || ev.date };

    $('editorTitle').textContent = isNew ? 'New event' : 'Edit event';
    $('fTitle').value = ev.title || '';
    $('fDate').value = ev.date;
    $('fAllDay').checked = !!ev.allDay;
    $('fStart').value = ev.start === null || ev.start === undefined ? '09:00'
      : String(Math.floor(ev.start / 60)).padStart(2, '0') + ':' + String(ev.start % 60).padStart(2, '0');
    $('fDuration').value = ev.duration || 60;
    $('fNotes').value = ev.notes || '';

    var select = $('fRepeat');
    var custom = select.querySelector('option[value="__custom"]');
    var value = repeatValue(ev.recurrence);
    if (value === '__custom') {
      if (!custom) {
        custom = document.createElement('option');
        custom.value = '__custom';
        select.appendChild(custom);
      }
      custom.textContent = describeRecurrence(ev.recurrence);
    } else if (custom) {
      custom.remove();
    }
    select.value = value;
    $('fUntil').value = ev.recurrence && ev.recurrence.until ? ev.recurrence.until : '';

    $('deleteFromEditor').hidden = isNew;
    syncTimeRow();
    $('editor').showModal();
    if (opts && opts.focusTitle) $('fTitle').focus();
    else $('fTitle').select();
  }

  function syncTimeRow() {
    var allDay = $('fAllDay').checked;
    $('timeRow').classList.toggle('disabled', allDay);
    $('fStart').disabled = allDay;
    $('fDuration').disabled = allDay;
    $('fUntil').disabled = !$('fRepeat').value;
  }

  function saveEditor() {
    var ev = editing.event;
    var title = $('fTitle').value.trim();
    if (!title) { $('fTitle').focus(); return false; }

    ev.title = title;
    ev.date = $('fDate').value || ev.date;
    ev.allDay = $('fAllDay').checked;
    if (ev.allDay) {
      ev.start = null;
    } else {
      var parts = ($('fStart').value || '09:00').split(':');
      ev.start = (+parts[0]) * 60 + (+parts[1]);
      ev.duration = Math.max(5, Math.min(1440, parseInt($('fDuration').value, 10) || 60));
    }
    ev.notes = $('fNotes').value.trim();

    var recurrence = repeatFromValue($('fRepeat').value, ev.date, ev.recurrence);
    if (recurrence) recurrence.until = $('fUntil').value || null;
    ev.recurrence = recurrence;
    if (!ev.exceptions) ev.exceptions = [];

    if (editing.isNew) {
      state.events.push(ev);
      toast('Added ' + describe(ev), 'Undo', function () { removeEvent(ev.id); });
    } else {
      toast('Saved “' + ev.title + '”', null, null);
    }
    save();
    state.selected = ev.date;
    state.view = new Date(keyToDate(ev.date).getFullYear(), keyToDate(ev.date).getMonth(), 1);
    render();
    editing = null;
    return true;
  }

  // ------------------------------------------------------------- speech

  var Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  var recognition = null;
  var listening = false;
  var wantListening = false;

  function speechSupported() {
    return !!Recognition && (window.isSecureContext || location.hostname === 'localhost' || location.hostname === '127.0.0.1');
  }

  function setStatus(text) { $('micStatus').textContent = text; }

  function setListening(on) {
    listening = on;
    $('micBtn').classList.toggle('listening', on);
    $('micBtn').setAttribute('aria-pressed', String(on));
    if (on) setStatus('Listening… say something like “lunch tomorrow at noon”.');
  }

  function initRecognition() {
    var rec = new Recognition();
    rec.lang = navigator.language || 'en-US';
    rec.continuous = false;
    rec.interimResults = true;
    rec.maxAlternatives = 1;

    rec.onstart = function () { setListening(true); };

    rec.onresult = function (event) {
      var interim = '';
      var final = '';
      for (var i = event.resultIndex; i < event.results.length; i++) {
        var text = event.results[i][0].transcript;
        if (event.results[i].isFinal) final += text;
        else interim += text;
      }
      $('transcript').textContent = (final || interim).trim();
      if (final.trim()) handleUtterance(final.trim());
    };

    rec.onerror = function (event) {
      if (event.error === 'no-speech') { setStatus('I didn’t hear anything — try again.'); return; }
      if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
        wantListening = false;
        $('handsFree').checked = false;
        setStatus('Microphone permission was blocked. Allow it in your browser, or type below.');
        return;
      }
      if (event.error === 'aborted') return;
      setStatus('Speech error: ' + event.error + '. You can still type below.');
    };

    rec.onend = function () {
      setListening(false);
      if (wantListening) {
        // hands-free: reopen the mic for the next sentence
        setTimeout(function () {
          if (!wantListening || listening) return;
          try { rec.start(); } catch (err) { /* already starting */ }
        }, 250);
      } else {
        setStatus('Press the mic and say what you want scheduled.');
      }
    };

    return rec;
  }

  function startListening() {
    if (!speechSupported()) return;
    if (!recognition) recognition = initRecognition();
    wantListening = $('handsFree').checked;
    $('transcript').textContent = '';
    try {
      recognition.start();
    } catch (err) {
      // start() throws if it is already running — treat the click as a stop
      stopListening();
    }
  }

  function stopListening() {
    wantListening = false;
    if (recognition) {
      try { recognition.stop(); } catch (err) { /* not running */ }
    }
    setListening(false);
    setStatus('Press the mic and say what you want scheduled.');
  }

  function say(text) {
    if (!state.settings.speak || !window.speechSynthesis) return;
    try {
      window.speechSynthesis.cancel();
      var utter = new SpeechSynthesisUtterance(text);
      utter.lang = navigator.language || 'en-US';
      utter.rate = 1.05;
      window.speechSynthesis.speak(utter);
    } catch (err) { /* voice output is optional */ }
  }

  // -------------------------------------------------- utterance handling

  function handleUtterance(text) {
    var parsed = P.parse(text, new Date());
    $('transcript').textContent = text;

    if (parsed.intent === 'delete') {
      deleteByPhrase(parsed);
      return;
    }
    if (!parsed.title) {
      setStatus('I caught the timing but not the name — fill it in and save.');
      openEditor(eventFromParsed(parsed), parsed.date, { focusTitle: true });
      return;
    }
    var ev = eventFromParsed(parsed);
    addEvent(ev);
    setStatus(parsed.matched.time
      ? 'Added “' + ev.title + '”. Say another, or press the mic again.'
      : 'Added “' + ev.title + '” as an all-day event — say a time to be specific.');
  }

  // ----------------------------------------------------------- ics export

  function icsEscape(text) {
    return String(text || '').replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');
  }

  function icsDate(key) { return key.replace(/-/g, ''); }

  function icsDateTime(key, minutes) {
    return icsDate(key) + 'T' + String(Math.floor(minutes / 60)).padStart(2, '0') +
      String(minutes % 60).padStart(2, '0') + '00';
  }

  function icsRule(r) {
    if (!r) return null;
    var names = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
    var parts = ['FREQ=' + r.freq.replace('ly', '').toUpperCase() + 'LY'];
    if (r.interval > 1) parts.push('INTERVAL=' + r.interval);
    if (r.byDay && r.byDay.length) parts.push('BYDAY=' + r.byDay.map(function (d) { return names[d]; }).join(','));
    if (r.until) parts.push('UNTIL=' + icsDate(r.until) + 'T235900');
    return 'RRULE:' + parts.join(';');
  }

  function exportIcs() {
    if (!state.events.length) {
      toast('Nothing to export yet.', null, null);
      return;
    }
    var stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    var lines = [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Voice Calendar//EN', 'CALSCALE:GREGORIAN'
    ];

    state.events.forEach(function (ev) {
      lines.push('BEGIN:VEVENT');
      lines.push('UID:' + ev.id + '@voice-calendar');
      lines.push('DTSTAMP:' + stamp);
      lines.push('SUMMARY:' + icsEscape(ev.title));
      if (ev.allDay || ev.start === null) {
        lines.push('DTSTART;VALUE=DATE:' + icsDate(ev.date));
        lines.push('DTEND;VALUE=DATE:' + icsDate(P.toKey(P.addDays(keyToDate(ev.date), 1))));
      } else {
        var endMin = ev.start + (ev.duration || 60);
        var endKey = ev.date;
        if (endMin >= 1440) {
          endKey = P.toKey(P.addDays(keyToDate(ev.date), Math.floor(endMin / 1440)));
          endMin = endMin % 1440;
        }
        lines.push('DTSTART:' + icsDateTime(ev.date, ev.start));
        lines.push('DTEND:' + icsDateTime(endKey, endMin));
      }
      var rule = icsRule(ev.recurrence);
      if (rule) lines.push(rule);
      if (ev.exceptions && ev.exceptions.length) {
        ev.exceptions.forEach(function (key) {
          lines.push(ev.allDay || ev.start === null
            ? 'EXDATE;VALUE=DATE:' + icsDate(key)
            : 'EXDATE:' + icsDateTime(key, ev.start));
        });
      }
      if (ev.notes) lines.push('DESCRIPTION:' + icsEscape(ev.notes));
      lines.push('END:VEVENT');
    });

    lines.push('END:VCALENDAR');

    var blob = new Blob([lines.join('\r\n') + '\r\n'], { type: 'text/calendar;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'voice-calendar.ics';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    toast('Exported ' + state.events.length + ' event' + (state.events.length === 1 ? '' : 's') + '.', null, null);
  }

  // --------------------------------------------------------------- wiring

  function moveMonth(delta) {
    state.view = new Date(state.view.getFullYear(), state.view.getMonth() + delta, 1);
    render();
  }

  function bind() {
    $('prevMonth').addEventListener('click', function () { moveMonth(-1); });
    $('nextMonth').addEventListener('click', function () { moveMonth(1); });
    $('todayBtn').addEventListener('click', function () {
      state.selected = todayKey();
      state.view = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
      render();
    });

    $('grid').addEventListener('click', function (event) {
      var chipEl = event.target.closest('.chip');
      if (chipEl) {
        var ev = state.events.find(function (e) { return e.id === chipEl.dataset.id; });
        if (ev) {
          state.selected = chipEl.dataset.date;
          render();
          openEditor(ev, chipEl.dataset.date);
        }
        return;
      }
      var cell = event.target.closest('.cell');
      if (cell) {
        state.selected = cell.dataset.date;
        render();
      }
    });

    $('grid').addEventListener('dblclick', function (event) {
      var cell = event.target.closest('.cell');
      if (cell && !event.target.closest('.chip')) openEditor(blankEvent(cell.dataset.date), cell.dataset.date, { focusTitle: true });
    });

    $('grid').addEventListener('keydown', function (event) {
      var cell = event.target.closest('.cell');
      if (!cell) return;
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        state.selected = cell.dataset.date;
        render();
      }
    });

    $('micBtn').addEventListener('click', function () {
      if (listening) stopListening();
      else startListening();
    });

    $('handsFree').addEventListener('change', function () {
      state.settings.handsFree = this.checked;
      save();
      if (!this.checked) wantListening = false;
      else if (listening) wantListening = true;
    });

    $('speakBack').addEventListener('change', function () {
      state.settings.speak = this.checked;
      save();
    });

    $('textForm').addEventListener('submit', function (event) {
      event.preventDefault();
      var text = $('textInput').value.trim();
      if (!text) return;
      $('textInput').value = '';
      handleUtterance(text);
    });

    $('newEvent').addEventListener('click', function () {
      openEditor(blankEvent(state.selected), state.selected, { focusTitle: true });
    });
    $('addOnDay').addEventListener('click', function () {
      openEditor(blankEvent(state.selected), state.selected, { focusTitle: true });
    });
    $('exportIcs').addEventListener('click', exportIcs);

    $('fAllDay').addEventListener('change', syncTimeRow);
    $('fRepeat').addEventListener('change', syncTimeRow);

    $('editorForm').addEventListener('submit', function (event) {
      if (!saveEditor()) event.preventDefault();
    });
    $('cancelEditor').addEventListener('click', function () {
      editing = null;
      $('editor').close();
    });
    $('deleteFromEditor').addEventListener('click', function () {
      var current = editing;
      $('editor').close();
      editing = null;
      if (current && !current.isNew) requestDelete(current.event, current.dateKey);
    });

    document.addEventListener('keydown', function (event) {
      var tag = (event.target.tagName || '').toLowerCase();
      var typing = tag === 'input' || tag === 'textarea' || tag === 'select';
      if (typing || event.metaKey || event.ctrlKey || event.altKey) return;
      if ($('editor').open || $('scopeDialog').open) return;

      if (event.key === 'ArrowLeft') { moveMonth(-1); }
      else if (event.key === 'ArrowRight') { moveMonth(1); }
      else if (event.key === 't') { $('todayBtn').click(); }
      else if (event.key === 'n') { event.preventDefault(); $('newEvent').click(); }
      else if (event.key === 'v') { $('micBtn').click(); }
    });

    EXAMPLES.forEach(function (phrase) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'example';
      b.textContent = '“' + phrase + '”';
      b.addEventListener('click', function () { handleUtterance(phrase); });
      $('examples').appendChild(b);
    });
  }

  // ----------------------------------------------------------------- init

  function init() {
    load();
    state.selected = todayKey();
    state.view = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    $('speakBack').checked = state.settings.speak;
    $('handsFree').checked = state.settings.handsFree;

    renderWeekdayHeader();
    bind();
    render();

    if (!Recognition) {
      $('micBtn').disabled = true;
      setStatus('This browser has no speech recognition (try Chrome or Edge) — typing below works the same.');
    } else if (!speechSupported()) {
      $('micBtn').disabled = true;
      setStatus('Dictation needs https or localhost. Serve this folder (python3 -m http.server) — or just type below.');
    }
  }

  document.addEventListener('DOMContentLoaded', init);
})();
