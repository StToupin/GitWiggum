import { Application } from "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3.2.2/+esm";
import AutoOpenModalController from "./controllers/auto_open_modal_controller.js";
import CopyFeedbackController from "./controllers/copy_feedback_controller.js";
import PullRequestSuggestionController from "./controllers/pull_request_suggestion_controller.js";
import RepositoryProjectBoardController from "./controllers/repository_project_board_controller.js";
import SidebarNavigationController from "./controllers/sidebar_navigation_controller.js";
import ThreadReplyComposerController from "./controllers/thread_reply_composer_controller.js";
import TooltipController from "./controllers/tooltip_controller.js";

const application = Application.start();

application.register("auto-open-modal", AutoOpenModalController);
application.register("copy-feedback", CopyFeedbackController);
application.register("pr-suggestion", PullRequestSuggestionController);
application.register("repository-project-board", RepositoryProjectBoardController);
application.register("sidebar-navigation", SidebarNavigationController);
application.register("thread-reply-composer", ThreadReplyComposerController);
application.register("tooltip", TooltipController);

window.Stimulus = application;
