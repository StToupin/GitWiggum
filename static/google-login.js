(function () {
  function currentMount() {
    return document.querySelector('[data-google-login-button]');
  }

  function clearLegalError(mount) {
    if (!mount) return;
    var legalErrorId = mount.getAttribute('data-legal-error-id');
    if (!legalErrorId) return;

    var errorNode = document.getElementById(legalErrorId);
    if (errorNode) {
      errorNode.textContent = '';
    }
  }

  function requireLegalConsent(mount, form) {
    if (!mount || !form) return true;

    var checkboxId = mount.getAttribute('data-legal-checkbox-id');
    if (!checkboxId) return true;

    var checkbox = document.getElementById(checkboxId);
    var accepted = Boolean(checkbox && checkbox.checked);

    if (accepted) {
      clearLegalError(mount);
      return true;
    }

    var legalErrorId = mount.getAttribute('data-legal-error-id');
    if (legalErrorId) {
      var errorNode = document.getElementById(legalErrorId);
      if (errorNode) {
        errorNode.textContent =
          errorNode.getAttribute('data-required-message') ||
          "You need to accept gitWiggum's legal terms before creating an account.";
      }
    }

    if (checkbox) {
      checkbox.focus();
    }

    return false;
  }

  function onGoogleLogin(response) {
    var mount = currentMount();
    if (!mount) return;

    var formId = mount.getAttribute('data-form-id');
    if (!formId) return;

    var form = document.getElementById(formId);
    if (!form || !response || !response.credential) return;

    if (!requireLegalConsent(mount, form)) return;

    var input = form.querySelector('input[name="jwt"]');
    if (!input) return;

    input.value = response.credential;
    form.submit();
  }

  function initGoogleButton() {
    var mount = currentMount();
    if (!mount) return;

    var clientId = mount.getAttribute("data-client-id");
    if (!clientId) return;

    if (!window.google || !window.google.accounts || !window.google.accounts.id) {
      return;
    }

    if (!window.__gitWiggumGoogleInitialized) {
      window.google.accounts.id.initialize({
        client_id: clientId,
        callback: onGoogleLogin,
        ux_mode: "popup",
        auto_select: false
      });
      window.__gitWiggumGoogleInitialized = true;
    }

    mount.innerHTML = "";

    window.google.accounts.id.renderButton(mount, {
      theme: "outline",
      size: "large",
      text: "continue_with",
      shape: "rectangular",
      width: mount.clientWidth,
      logo_alignment: "left"
    });
  }

  function scheduleGoogleInit() {
    if (!window.google) {
      var gsiScript = document.querySelector('script[src*="https://accounts.google.com/gsi/client"]');
      if (gsiScript && !gsiScript.__gitWiggumGoogleBound) {
        gsiScript.__gitWiggumGoogleBound = true;
        gsiScript.addEventListener("load", initGoogleButton);
      }
    }

    initGoogleButton();
  }

  document.addEventListener("DOMContentLoaded", scheduleGoogleInit);
  document.addEventListener("ihp:load", scheduleGoogleInit);
  document.addEventListener("htmx:afterSwap", scheduleGoogleInit);
  window.addEventListener("load", scheduleGoogleInit);
})();
