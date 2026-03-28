import { Controller } from "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/+esm";

export default class extends Controller {
    connect() {
        this.boundHandleHtmxLoad = this.handleHtmxLoad.bind(this);
        document.addEventListener("htmx:load", this.boundHandleHtmxLoad);
        document.addEventListener("htmx:afterSwap", this.boundHandleHtmxLoad);
        this.maybeShow();
    }

    disconnect() {
        if (this.boundHandleHtmxLoad) {
            document.removeEventListener("htmx:load", this.boundHandleHtmxLoad);
            document.removeEventListener("htmx:afterSwap", this.boundHandleHtmxLoad);
            this.boundHandleHtmxLoad = null;
        }
    }

    handleHtmxLoad(event) {
        this.maybeShow();
    }

    maybeShow() {
        if (!window.bootstrap || !window.bootstrap.Modal) {
            return;
        }

        if (this.element.dataset.openModalOnLoad !== "true") {
            return;
        }

        if (this.element.dataset.autoOpenModalShown === "true") {
            return;
        }

        const existingInstance = window.bootstrap.Modal.getInstance(this.element);
        if (existingInstance && existingInstance._isShown && !this.element.classList.contains("show")) {
            existingInstance.dispose();
        }

        window.bootstrap.Modal.getOrCreateInstance(this.element).show();
        this.element.dataset.autoOpenModalShown = "true";
    }
}
