// Site-wide JavaScript

document.addEventListener('DOMContentLoaded', function() {
  // Initialize Bootstrap tooltips
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function(el) {
    new bootstrap.Tooltip(el, { trigger: 'hover' });
  });

  document.addEventListener('click', function(e) {
    // Copy path button: [data-copy-path]
    var btn = e.target;
    if (btn.tagName === 'IMG' && btn.parentElement.hasAttribute('data-copy-path')) {
      btn = btn.parentElement;
    }
    if (btn.hasAttribute('data-copy-path')) {
      var path = btn.dataset.copyPath;
      var img = btn.querySelector('img');
      if (!path || !img) return;

      var baseUrl = document.body.dataset.baseurl || '';
      var copySrc = img.getAttribute('src');
      var checkSrc = baseUrl + '/assets/images/check.svg';

      navigator.clipboard.writeText(path).then(function() {
        img.setAttribute('src', checkSrc);
        btn.style.opacity = '1';
        setTimeout(function() {
          img.setAttribute('src', copySrc);
          btn.style.opacity = '';
        }, 1000);
      });
      return;
    }

    // In-page anchor links: scroll to center of viewport
    var link = e.target;
    if (link.tagName !== 'A') {
      link = e.target.parentElement;
      if (!link || link.tagName !== 'A') return;
    }
    var href = link.getAttribute('href');
    if (!href || !href.startsWith('#') || href === '#') return;

    var target = document.querySelector(href);
    if (!target) return;

    e.preventDefault();
    target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    history.pushState(null, '', href);
  });
});
