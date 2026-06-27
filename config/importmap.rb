# Pin npm packages by running ./bin/importmap
#
# The public layout loads JavaScript from CDN (jQuery, Bootstrap, Chart.js).
# Importmap pins are kept minimal until the app adopts javascript_importmap_tags.

pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
