import { application } from "./application"

import DropdownController from "./dropdown_controller"
application.register("dropdown", DropdownController)

// Eager load all controllers defined in the import map under controllers/**/*_controller
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application);
