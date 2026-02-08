(function() {
  'use strict';

  function initNavBreadcrumb() {
    var sidebar = document.getElementById('sidebar');
    var breadcrumb = document.getElementById('nav-breadcrumb');
    var apiNav = sidebar.querySelector('[data-nav]');

    if (!sidebar || !breadcrumb || !apiNav) return;

    var navLinks = apiNav.querySelectorAll('.nav-nested .nav-link');

    function updateBreadcrumb() {
      var sidebarRect = sidebar.getBoundingClientRect();
      var topThreshold = sidebarRect.top + 80; // Below the breadcrumb area

      var currentItem = null;

      // Find the first nav link that's below the top threshold
      for (var i = 0; i < navLinks.length; i++) {
        var rect = navLinks[i].getBoundingClientRect();
        if (rect.top >= topThreshold) {
          // Use the previous item (last one scrolled past)
          currentItem = i > 0 ? navLinks[i - 1] : null;
          break;
        }
        currentItem = navLinks[i];
      }

      if (!currentItem) {
        breadcrumb.removeAttribute('data-visible');
        breadcrumb.innerHTML = '';
        return;
      }

      // Build breadcrumb from parent nav items
      var parents = [];
      var el = currentItem.closest('.nav-nested');

      while (el) {
        var parentLi = el.closest('.nav-item');
        if (parentLi) {
          var parentLink = parentLi.querySelector(':scope > .nav-link');
          if (parentLink && parentLink !== currentItem) {
            parents.unshift({
              text: parentLink.textContent.replace('▾', '').trim(),
              href: parentLink.getAttribute('href')
            });
          }
        }
        el = el.parentElement ? el.parentElement.closest('.nav-nested') : null;
      }

      if (parents.length === 0) {
        breadcrumb.removeAttribute('data-visible');
        breadcrumb.innerHTML = '';
        return;
      }

      var html = parents.map(function(p) {
        return '<a href="' + p.href + '">' + p.text + '</a>';
      }).join(' <span class="text-muted">›</span> ');

      breadcrumb.innerHTML = html;
      breadcrumb.setAttribute('data-visible', '');
    }

    // Throttle scroll events
    var ticking = false;
    sidebar.addEventListener('scroll', function() {
      if (!ticking) {
        window.requestAnimationFrame(function() {
          updateBreadcrumb();
          ticking = false;
        });
        ticking = true;
      }
    });

    // Initial update
    updateBreadcrumb();
  }

  // Init on load and after Turbo navigation
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initNavBreadcrumb);
  } else {
    initNavBreadcrumb();
  }
  document.addEventListener('turbo:load', initNavBreadcrumb);
})();
