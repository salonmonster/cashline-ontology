# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "mermaid", to: "https://cdn.jsdelivr.net/npm/mermaid@11/+esm"
pin "cytoscape", to: "https://cdn.jsdelivr.net/npm/cytoscape@3.30/+esm"
pin "cytoscape-fcose", to: "https://cdn.jsdelivr.net/npm/cytoscape-fcose@2.2/+esm"
