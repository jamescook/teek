(function() {
  'use strict';

  var searchData = null;
  var searchIndex = null;
  var selectedIndex = -1;
  var lastNavTime = 0;
  var navDelay = 80; // ms delay when holding arrow keys
  var currentInput = null;
  var savedScrollTop = 0;

  // Load search data once
  var baseUrl = document.body.dataset.baseurl || '';
  fetch(baseUrl + '/assets/js/search-data.json')
    .then(function(response) { return response.json(); })
    .then(function(data) {
      searchData = data;
      searchIndex = lunr(function() {
        this.ref('id');
        this.field('title', { boost: 100 });
        this.field('methods', { boost: 10 });
        this.field('content');

        Object.keys(data).forEach(function(key) {
          this.add({
            id: key,
            title: data[key].title,
            methods: data[key].methods,
            content: data[key].content
          });
        }, this);
      });
    });

  function initSearch() {
    var searchInput = document.getElementById('search-input');
    var searchResults = document.getElementById('search-results');

    if (!searchInput || !searchResults) return;

    // Skip if we already bound listeners to this exact element
    if (searchInput === currentInput) return;
    currentInput = searchInput;

    function updateSelection() {
      var items = searchResults.querySelectorAll('[data-search-result]');
      items.forEach(function(item, i) {
        item.toggleAttribute('data-selected', i === selectedIndex);
      });
      if (selectedIndex >= 0 && items[selectedIndex]) {
        var item = items[selectedIndex];
        var container = searchResults;
        var itemTop = item.offsetTop;
        var itemBottom = itemTop + item.offsetHeight;
        if (itemTop < container.scrollTop) {
          container.scrollTop = itemTop;
        } else if (itemBottom > container.scrollTop + container.clientHeight) {
          container.scrollTop = itemBottom - container.clientHeight;
        }
      }
    }

    function handleSearchKey(key, isRepeat) {
      if (key === 'Escape' && searchResults.style.display !== 'none') {
        searchResults.style.display = 'none';
        selectedIndex = -1;
        return true;
      }

      var items = searchResults.querySelectorAll('[data-search-result]');
      if (!items.length) return false;

      if (key === 'ArrowDown' || key === 'ArrowUp') {
        // Throttle when key is held down
        var now = Date.now();
        if (isRepeat && now - lastNavTime < navDelay) return true;
        lastNavTime = now;

        if (key === 'ArrowDown') {
          selectedIndex = selectedIndex < items.length - 1 ? selectedIndex + 1 : 0;
        } else {
          selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : items.length - 1;
        }
        updateSelection();
        return true;
      } else if (key === 'Enter') {
        if (selectedIndex >= 0) {
          items[selectedIndex].click();
          return true;
        } else if (items.length === 1) {
          items[0].click();
          return true;
        }
      }
      return false;
    }

    searchInput.addEventListener('keydown', function(e) {
      if (handleSearchKey(e.key, e.repeat)) {
        e.preventDefault();
      }
    });

    searchInput.addEventListener('input', function() {
      selectedIndex = -1;
      var query = this.value.trim();

      if (query.length < 2) {
        searchResults.innerHTML = '';
        searchResults.style.display = 'none';
        return;
      }

      if (!searchIndex) return;

      var phraseMatch = query.match(/^"(.+)"$/);
      var phrase = phraseMatch ? phraseMatch[1].toLowerCase() : null;
      var lunrQuery = query;

      if (phrase) {
        lunrQuery = phrase.split(/\s+/).map(function(w) { return '+' + w; }).join(' ');
      } else {
        lunrQuery = query + ' ' + query + '*';
      }

      var results = searchIndex.search(lunrQuery);

      if (phrase) {
        results = results.filter(function(r) {
          var doc = searchData[r.ref];
          var all = (doc.title + ' ' + doc.methods + ' ' + doc.content).toLowerCase();
          return all.includes(phrase);
        });
      }

      if (results.length === 0) {
        searchResults.innerHTML = '<div class="search-result-item">No results found</div>';
        searchResults.style.display = 'block';
        return;
      }

      var queryLower = query.toLowerCase();

      results.sort(function(a, b) {
        var docA = searchData[a.ref];
        var docB = searchData[b.ref];
        var titleA = docA.title.toLowerCase();
        var titleB = docB.title.toLowerCase();
        var lenA = docA.title.length;
        var lenB = docB.title.length;

        // 1. Exact title match
        var aExact = titleA === queryLower;
        var bExact = titleB === queryLower;
        if (aExact && !bExact) return -1;
        if (bExact && !aExact) return 1;

        // 2. Title contains query (shorter names first)
        var aTitle = titleA.includes(queryLower);
        var bTitle = titleB.includes(queryLower);
        if (aTitle && !bTitle) return -1;
        if (bTitle && !aTitle) return 1;
        if (aTitle && bTitle) return lenA - lenB;

        // 3. Method name matches (shorter names first)
        var aMethod = (docA.methods || '').toLowerCase().includes(queryLower);
        var bMethod = (docB.methods || '').toLowerCase().includes(queryLower);
        if (aMethod && !bMethod) return -1;
        if (bMethod && !aMethod) return 1;
        if (aMethod && bMethod) return lenA - lenB;

        // 4. Docstring matches (shorter names first)
        return lenA - lenB || b.score - a.score;
      });

      // Expand each class/module result into per-method entries when methods match
      var entries = [];
      results.forEach(function(result) {
        var doc = searchData[result.ref];
        var badge = doc.type === 'module' ? '<span class="badge bg-success">M</span>' : '<span class="badge bg-primary">C</span>';
        var titleLower = doc.title.toLowerCase();
        var isCurrent = (baseUrl + doc.url) === window.location.pathname || (baseUrl + doc.url + '/') === window.location.pathname;
        var currentAttr = isCurrent ? ' data-current' : '';

        if (titleLower.includes(queryLower)) {
          // Class/module name matches — show as-is
          entries.push('<a href="' + baseUrl + doc.url + '" class="search-result-item" data-search-result data-turbo-frame="_top"' + currentAttr + '>' + badge + ' <span class="search-title">' + doc.title + '</span></a>');
        }

        // Find all matching methods — each gets its own entry
        var methodNames = (doc.methods || '').split(/\s+/).filter(function(m) {
          return m && m.toLowerCase().indexOf(queryLower) !== -1;
        });
        methodNames.forEach(function(m) {
          var snippet = '<span class="search-snippet">#' + m + '</span>';
          entries.push('<a href="' + baseUrl + doc.url + '#method-' + m + '" class="search-result-item" data-search-result data-turbo-frame="_top"' + currentAttr + '>' + badge + ' <span class="search-title">' + doc.title + '</span>' + snippet + '</a>');
        });

        // Docstring matches — find methods whose docstrings contain the query
        if (!titleLower.includes(queryLower) && methodNames.length === 0) {
          var methodDocs = doc.method_docs || {};
          var docMatches = Object.keys(methodDocs).filter(function(name) {
            return methodDocs[name].toLowerCase().indexOf(queryLower) !== -1;
          });

          if (docMatches.length > 0) {
            docMatches.forEach(function(name) {
              var ds = methodDocs[name].toLowerCase();
              var mi = ds.indexOf(queryLower);
              var start = Math.max(0, mi - 15);
              var end = Math.min(mi + queryLower.length + 25, methodDocs[name].length);
              var ctx = methodDocs[name].substring(start, end).trim();
              if (start > 0) ctx = '...' + ctx;
              if (end < methodDocs[name].length) ctx += '...';
              var snippet = '<span class="search-snippet">#' + name + ' — ' + ctx + '</span>';
              entries.push('<a href="' + baseUrl + doc.url + '#method-' + name + '" class="search-result-item" data-search-result data-turbo-frame="_top"' + currentAttr + '>' + badge + ' <span class="search-title">' + doc.title + '</span>' + snippet + '</a>');
            });
          } else {
            // No specific method found — link to class page
            entries.push('<a href="' + baseUrl + doc.url + '" class="search-result-item" data-search-result data-turbo-frame="_top"' + currentAttr + '>' + badge + ' <span class="search-title">' + doc.title + '</span></a>');
          }
        }
      });

      var html = entries.slice(0, 25).join('');

      searchResults.innerHTML = html;
      searchResults.style.display = 'block';
    });

    function updateCurrentMarker() {
      var items = searchResults.querySelectorAll('[data-search-result]');
      items.forEach(function(item) {
        var href = item.getAttribute('href');
        var isCurrent = href === window.location.pathname || (href + '/') === window.location.pathname;
        item.toggleAttribute('data-current', isCurrent);
      });
    }

    searchInput.addEventListener('focus', function() {
      if (this.value.trim().length >= 2 && searchResults.innerHTML) {
        searchResults.style.display = 'block';
        // Update current page marker and restore scroll/selection
        updateCurrentMarker();
        searchResults.scrollTop = savedScrollTop;
        if (selectedIndex >= 0) {
          updateSelection();
        }
      }
    });

    searchResults.addEventListener('scroll', function() {
      savedScrollTop = searchResults.scrollTop;
    });

    // Keep focus on input when clicking in results (but allow link clicks to work)
    searchResults.addEventListener('mousedown', function(e) {
      if (e.target.closest('a')) return; // let links work normally
      e.preventDefault(); // prevent focus moving away from input
    });

    // Handle arrow/escape/enter on results container (in case focus lands there)
    searchResults.addEventListener('keydown', function(e) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Escape' || e.key === 'Enter') {
        e.preventDefault();
        e.stopPropagation();
        handleSearchKey(e.key, e.repeat);
        searchInput.focus();
      }
    });

    document.addEventListener('click', function(e) {
      if (!searchInput.contains(e.target) && !searchResults.contains(e.target)) {
        searchResults.style.display = 'none';
      }
    });
  }

  function updateCurrentMarkerGlobal() {
    var searchResults = document.getElementById('search-results');
    if (!searchResults) return;
    var items = searchResults.querySelectorAll('[data-search-result]');
    items.forEach(function(item) {
      var href = item.getAttribute('href');
      var isCurrent = href === window.location.pathname || (href + '/') === window.location.pathname;
      item.toggleAttribute('data-current', isCurrent);
    });
  }

  // Init on first load and after Turbo navigation
  initSearch();
  document.addEventListener('turbo:load', function() {
    initSearch();
    updateCurrentMarkerGlobal();
  });
})();
