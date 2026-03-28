(function () {
  function signupForm() {
    return document.getElementById('new-user-form');
  }

  function isSignupFormElement(element) {
    if (!element) return false;
    if (element.id === 'new-user-form') return true;
    return Boolean(element.closest && element.closest('#new-user-form'));
  }

  function legalCheckbox() {
    return document.getElementById('user_accepted_legal');
  }

  function legalErrorNode() {
    return document.getElementById('signup-legal-error');
  }

  function syncGoogleSignupButtons() {
    var checkbox = legalCheckbox();
    var accepted = Boolean(checkbox && checkbox.checked);

    document.querySelectorAll('[data-signup-google-button]').forEach(function (button) {
      button.hidden = accepted;
      button.tabIndex = accepted ? -1 : 0;
    });
  }

  function clearLegalError() {
    var node = legalErrorNode();
    if (node) {
      node.textContent = '';
    }
  }

  function showLegalError() {
    var node = legalErrorNode();
    if (!node) return;

    node.textContent =
      node.getAttribute('data-required-message') ||
      "You need to accept gitWiggum's legal terms before creating an account.";
  }

  function requireLegalConsent() {
    var checkbox = legalCheckbox();
    var accepted = Boolean(checkbox && checkbox.checked);

    if (accepted) {
      clearLegalError();
      return true;
    }

    showLegalError();
    if (checkbox) {
      checkbox.focus();
    }
    return false;
  }

  function bindSignupHandlers() {
    var form = signupForm();
    var checkbox = legalCheckbox();

    if (checkbox && !checkbox.__gitWiggumLegalBound) {
      checkbox.__gitWiggumLegalBound = true;
      checkbox.addEventListener('change', function () {
        syncGoogleSignupButtons();
        if (checkbox.checked) {
          clearLegalError();
        }
      });
    }

    if (form && !form.__gitWiggumLegalBound) {
      form.__gitWiggumLegalBound = true;
      form.addEventListener('submit', function (event) {
        if (!requireLegalConsent()) {
          event.preventDefault();
        }
      });

      form
        .querySelectorAll('button[type="submit"], input[type="submit"]')
        .forEach(function (button) {
          if (button.__gitWiggumLegalBound) return;

          button.__gitWiggumLegalBound = true;
          button.addEventListener('click', function (event) {
            if (!requireLegalConsent()) {
              event.preventDefault();
            }
          });
        });
    }

    document.querySelectorAll('[data-signup-github-button]').forEach(function (button) {
      if (button.__gitWiggumLegalBound) return;

      button.__gitWiggumLegalBound = true;
      button.addEventListener('click', function () {
        if (!requireLegalConsent()) {
          return;
        }

        var formId = button.getAttribute('data-form-id');
        var targetForm = formId ? document.getElementById(formId) : null;
        if (targetForm) {
          targetForm.submit();
        }
      });
    });

    document.querySelectorAll('[data-signup-google-button]').forEach(function (button) {
      if (button.__gitWiggumLegalBound) return;

      button.__gitWiggumLegalBound = true;
      button.addEventListener('click', function () {
        requireLegalConsent();
      });
    });

    syncGoogleSignupButtons();
  }

  function bindSignupHtmxGuard() {
    if (document.__gitWiggumLegalHtmxBound) return;

    document.__gitWiggumLegalHtmxBound = true;
    document.addEventListener('htmx:beforeRequest', function (event) {
      var trigger = event && event.detail ? event.detail.elt : null;
      if (!isSignupFormElement(trigger)) return;

      if (!requireLegalConsent()) {
        event.preventDefault();
      }
    });
  }

  document.addEventListener('DOMContentLoaded', bindSignupHandlers);
  document.addEventListener('ihp:load', bindSignupHandlers);
  document.addEventListener('htmx:afterSwap', bindSignupHandlers);
  window.addEventListener('load', bindSignupHandlers);
  bindSignupHtmxGuard();
})();
