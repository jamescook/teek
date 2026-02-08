(function() {
  'use strict';

  var SIDEBAR_ID = 'sidebar';

  function nav() {
    var sidebar = document.getElementById(SIDEBAR_ID);
    return sidebar ? sidebar.querySelector('[data-nav]') : document.querySelector('[data-nav]');
  }

  function findActiveLink() {
    var el = nav();
    if (!el) return null;

    var path = window.location.pathname;
    var link = el.querySelector('[data-nav-link][href="' + path + '"]');
    if (!link) {
      var alt = path.endsWith('/') ? path.slice(0, -1) : path + '/';
      link = el.querySelector('[data-nav-link][href="' + alt + '"]');
    }
    return link;
  }

  function expandCollapse(collapseId) {
    var el = nav();
    if (!el) return;

    var collapseEl = el.querySelector('#' + collapseId);
    if (!collapseEl || collapseEl.classList.contains('show')) return;

    collapseEl.classList.add('show');
    var chevron = el.querySelector('[data-nav-chevron="' + collapseId + '"]');
    if (chevron) {
      chevron.classList.remove('collapsed');
      chevron.setAttribute('aria-expanded', 'true');
    }
  }

  function updateActiveMarker() {
    var el = nav();
    if (!el) return;

    var prev = el.querySelector('[data-nav-item][data-active]');
    if (prev) prev.removeAttribute('data-active');

    var link = findActiveLink();
    if (!link) return;

    var item = link.closest('[data-nav-item]');
    if (item) item.setAttribute('data-active', '');
  }

  function expandAncestors() {
    var el = nav();
    if (!el) return;

    var link = findActiveLink();
    if (!link) return;

    var item = link.closest('[data-nav-item]');
    if (!item) return;

    // Walk up the data-parent chain
    var parentPath = item.getAttribute('data-parent');
    while (parentPath) {
      var collapseEl = el.querySelector('[data-collapse-for="' + parentPath + '"]');
      if (collapseEl) expandCollapse(collapseEl.id);

      var parentItem = el.querySelector('[data-nav-item][data-path="' + parentPath + '"]');
      parentPath = parentItem ? parentItem.getAttribute('data-parent') : null;
    }

    item.setAttribute('data-active', '');

    // Scroll into view only if not visible
    var sidebar = document.getElementById(SIDEBAR_ID);
    if (sidebar) {
      var sidebarRect = sidebar.getBoundingClientRect();
      var linkRect = link.getBoundingClientRect();
      if (linkRect.top < sidebarRect.top || linkRect.bottom > sidebarRect.bottom) {
        link.scrollIntoView({ block: 'center' });
      }
    }
  }

  // Clicking a parent nav link also expands its immediate children
  document.addEventListener('click', function(e) {
    var link = e.target.closest('[data-expand-target]');
    if (!link) return;

    var targetId = link.getAttribute('data-expand-target');
    if (targetId) expandCollapse(targetId);
  });

  // Full page load: expand ancestors and set active marker
  function onFullLoad() {
    expandAncestors();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onFullLoad);
  } else {
    onFullLoad();
  }
  document.addEventListener('turbo:load', onFullLoad);

  // Turbo frame navigation: update active marker after URL has changed
  document.addEventListener('turbo:frame-load', function(e) {
    if (e.target.id === 'main-content') {
      requestAnimationFrame(function() { updateActiveMarker(); });
    }
  });
})();
