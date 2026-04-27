defmodule MobileCarWashWeb.Admin.StyleGuideLive do
  @moduledoc """
  Living style guide — color palette, component library, and sizing guidelines.
  """
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Style Guide")
     |> assign(demo_modal_open: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <h1 class="text-4xl font-bold mb-2">Style Guide</h1>
      <p class="text-base-content/80 mb-8">Brand colors, component library, and sizing guidelines.</p>
      
    <!-- TABLE OF CONTENTS -->
      <div class="flex flex-wrap gap-2 mb-12">
        <a href="#colors" class="btn btn-sm btn-outline">Colors</a>
        <a href="#typography" class="btn btn-sm btn-outline">Typography</a>
        <a href="#buttons" class="btn btn-sm btn-outline">Buttons</a>
        <a href="#cards" class="btn btn-sm btn-outline">Cards</a>
        <a href="#badges" class="btn btn-sm btn-outline">Badges</a>
        <a href="#alerts" class="btn btn-sm btn-outline">Alerts</a>
        <a href="#forms" class="btn btn-sm btn-outline">Forms</a>
        <a href="#shadows" class="btn btn-sm btn-outline">Shadows</a>
        <a href="#spacing" class="btn btn-sm btn-outline">Spacing</a>
        <a href="#button-variants" class="btn btn-sm btn-outline">Button Variants</a>
        <a href="#status-pills" class="btn btn-sm btn-outline">Status Pills</a>
        <a href="#progress-bars" class="btn btn-sm btn-outline">Progress Bars</a>
        <a href="#flash-messages" class="btn btn-sm btn-outline">Flash</a>
        <a href="#empty-state" class="btn btn-sm btn-outline">Empty State</a>
        <a href="#kpi-card" class="btn btn-sm btn-outline">KPI Card</a>
        <a href="#bucket-cards" class="btn btn-sm btn-outline">Bucket Cards</a>
        <a href="#modal" class="btn btn-sm btn-outline">Modal</a>
      </div>
      
    <!-- ============================================================ -->
      <!-- COLOR PALETTE -->
      <!-- ============================================================ -->
      <section id="colors" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Color Palette</h2>
        
    <!-- Primary — Navy -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-1">Primary — Navy</h3>
          <p class="text-sm text-base-content/80 mb-3">
            Base: #1E2A38 (700). Used for headers, primary actions, and brand identity.
          </p>
          <div class="grid grid-cols-5 md:grid-cols-10 gap-1">
            <.swatch hex="#F0F2F5" label="50" dark={false} />
            <.swatch hex="#D4DAE2" label="100" dark={false} />
            <.swatch hex="#A9B5C5" label="200" dark={false} />
            <.swatch hex="#7E91A8" label="300" dark={false} />
            <.swatch hex="#536C8B" label="400" dark={true} />
            <.swatch hex="#2E4A66" label="500" dark={true} />
            <.swatch hex="#253D55" label="600" dark={true} />
            <.swatch hex="#1E2A38" label="700" dark={true} />
            <.swatch hex="#151E28" label="800" dark={true} />
            <.swatch hex="#0C1219" label="900" dark={true} />
          </div>
        </div>
        
    <!-- Secondary — White/Neutral -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-1">Secondary — White / Neutral</h3>
          <p class="text-sm text-base-content/80 mb-3">
            Base: #FFFFFF (50). Used for backgrounds, cards, and clean space.
          </p>
          <div class="grid grid-cols-5 md:grid-cols-10 gap-1">
            <.swatch hex="#FFFFFF" label="50" dark={false} border={true} />
            <.swatch hex="#F8F9FA" label="100" dark={false} />
            <.swatch hex="#E9ECEF" label="200" dark={false} />
            <.swatch hex="#DEE2E6" label="300" dark={false} />
            <.swatch hex="#CED4DA" label="400" dark={false} />
            <.swatch hex="#ADB5BD" label="500" dark={false} />
            <.swatch hex="#868E96" label="600" dark={true} />
            <.swatch hex="#495057" label="700" dark={true} />
            <.swatch hex="#343A40" label="800" dark={true} />
            <.swatch hex="#212529" label="900" dark={true} />
          </div>
        </div>
        
    <!-- Tertiary — Steel Blue -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-1">Tertiary — Steel Blue</h3>
          <p class="text-sm text-base-content/80 mb-3">
            Base: #3A7CA5 (400). Used for links, interactive elements, and accent touches.
          </p>
          <div class="grid grid-cols-5 md:grid-cols-10 gap-1">
            <.swatch hex="#EBF4F9" label="50" dark={false} />
            <.swatch hex="#C8E1EF" label="100" dark={false} />
            <.swatch hex="#93C5DF" label="200" dark={false} />
            <.swatch hex="#5EA8CF" label="300" dark={false} />
            <.swatch hex="#3A7CA5" label="400" dark={true} />
            <.swatch hex="#317193" label="500" dark={true} />
            <.swatch hex="#2E6384" label="600" dark={true} />
            <.swatch hex="#234A63" label="700" dark={true} />
            <.swatch hex="#183242" label="800" dark={true} />
            <.swatch hex="#0D1A21" label="900" dark={true} />
          </div>
        </div>
        
    <!-- DaisyUI Semantic Colors -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-1">Semantic Colors (DaisyUI)</h3>
          <p class="text-sm text-base-content/80 mb-3">
            Mapped from brand palette. Adapt to light/dark theme automatically.
          </p>
          <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-primary"></div>
              <span class="text-xs font-mono">primary</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-secondary"></div>
              <span class="text-xs font-mono">secondary</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-accent"></div>
              <span class="text-xs font-mono">accent</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-neutral"></div>
              <span class="text-xs font-mono">neutral</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-info"></div>
              <span class="text-xs font-mono">info</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-success"></div>
              <span class="text-xs font-mono">success</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-warning"></div>
              <span class="text-xs font-mono">warning</span>
            </div>
            <div class="flex flex-col items-center gap-1">
              <div class="w-full h-16 rounded-lg bg-error"></div>
              <span class="text-xs font-mono">error</span>
            </div>
          </div>
        </div>
        
    <!-- Color Usage Reference -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-3">Tailwind Class Reference</h3>
          <p class="text-sm text-base-content/80 mb-4">
            Every shade is a real Tailwind utility. Use them with any property prefix: <code class="bg-base-200 px-1 rounded">bg-</code>, <code class="bg-base-200 px-1 rounded">text-</code>, <code class="bg-base-200 px-1 rounded">border-</code>, <code class="bg-base-200 px-1 rounded">ring-</code>, etc.
          </p>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Palette</th>
                  <th>Class Pattern</th>
                  <th>Example</th>
                  <th>Preview</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td class="font-semibold">Primary (Navy)</td>
                  <td class="font-mono text-xs">bg-primary-{50 - 900}</td>
                  <td class="font-mono text-xs">bg-primary-700, text-primary-200</td>
                  <td>
                    <div class="flex gap-1">
                      <div class="w-5 h-5 rounded bg-primary-100"></div>
                      <div class="w-5 h-5 rounded bg-primary-300"></div>
                      <div class="w-5 h-5 rounded bg-primary-500"></div>
                      <div class="w-5 h-5 rounded bg-primary-700"></div>
                      <div class="w-5 h-5 rounded bg-primary-900"></div>
                    </div>
                  </td>
                </tr>
                <tr>
                  <td class="font-semibold">Secondary (Neutral)</td>
                  <td class="font-mono text-xs">bg-secondary-{50 - 900}</td>
                  <td class="font-mono text-xs">bg-secondary-100, border-secondary-300</td>
                  <td>
                    <div class="flex gap-1">
                      <div class="w-5 h-5 rounded bg-secondary-100 border border-secondary-300"></div>
                      <div class="w-5 h-5 rounded bg-secondary-300"></div>
                      <div class="w-5 h-5 rounded bg-secondary-500"></div>
                      <div class="w-5 h-5 rounded bg-secondary-700"></div>
                      <div class="w-5 h-5 rounded bg-secondary-900"></div>
                    </div>
                  </td>
                </tr>
                <tr>
                  <td class="font-semibold">Tertiary (Steel Blue)</td>
                  <td class="font-mono text-xs">bg-tertiary-{50 - 900}</td>
                  <td class="font-mono text-xs">bg-tertiary-400, text-tertiary-600</td>
                  <td>
                    <div class="flex gap-1">
                      <div class="w-5 h-5 rounded bg-tertiary-100"></div>
                      <div class="w-5 h-5 rounded bg-tertiary-300"></div>
                      <div class="w-5 h-5 rounded bg-tertiary-400"></div>
                      <div class="w-5 h-5 rounded bg-tertiary-600"></div>
                      <div class="w-5 h-5 rounded bg-tertiary-900"></div>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        
    <!-- Common Patterns -->
        <div class="mb-8">
          <h3 class="text-lg font-semibold mb-3">Common Patterns</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="rounded-lg border border-secondary-300 overflow-hidden">
              <div class="bg-primary-700 text-primary-100 p-4">
                <h4 class="font-bold">Dark header on Navy</h4>
                <p class="text-sm text-primary-200">bg-primary-700 text-primary-100</p>
              </div>
              <div class="bg-secondary-50 p-4">
                <p class="text-primary-800">Content area — bg-secondary-50 text-primary-800</p>
              </div>
            </div>

            <div class="rounded-lg border border-tertiary-200 overflow-hidden">
              <div class="bg-tertiary-50 p-4 border-b border-tertiary-200">
                <h4 class="font-bold text-tertiary-700">Info section on Steel Blue tint</h4>
                <p class="text-sm text-tertiary-600">bg-tertiary-50 text-tertiary-700</p>
              </div>
              <div class="bg-secondary-50 p-4">
                <p class="text-secondary-800">Content — bg-secondary-50 text-secondary-800</p>
              </div>
            </div>

            <div class="rounded-lg bg-secondary-100 p-4 border border-secondary-300">
              <h4 class="font-bold text-primary-700">Subtle card</h4>
              <p class="text-sm text-secondary-600">bg-secondary-100 border-secondary-300</p>
              <button class="mt-2 px-4 py-2 bg-tertiary-400 text-white rounded-lg text-sm font-medium">
                CTA — bg-tertiary-400
              </button>
            </div>

            <div class="rounded-lg bg-primary-800 p-4">
              <h4 class="font-bold text-secondary-100">Dark card</h4>
              <p class="text-sm text-secondary-400">bg-primary-800 text-secondary-400</p>
              <button class="mt-2 px-4 py-2 bg-tertiary-400 text-white rounded-lg text-sm font-medium">
                CTA — bg-tertiary-400
              </button>
            </div>
          </div>
        </div>
        
    <!-- Quick Reference -->
        <div class="bg-base-200 rounded-lg p-4 text-sm mb-8">
          <h4 class="font-semibold mb-2">When to use each palette:</h4>
          <table class="table table-sm">
            <tbody>
              <tr>
                <td class="font-semibold w-32">Primary 50-200</td>
                <td>Light backgrounds, hover tints, disabled states</td>
              </tr>
              <tr>
                <td class="font-semibold">Primary 300-500</td>
                <td>Secondary text, borders, icons</td>
              </tr>
              <tr>
                <td class="font-semibold">Primary 600-900</td>
                <td>Headings, body text, dark sections, navbar</td>
              </tr>
              <tr>
                <td class="font-semibold">Secondary 50-200</td>
                <td>Page backgrounds, card surfaces, clean space</td>
              </tr>
              <tr>
                <td class="font-semibold">Secondary 300-500</td>
                <td>Borders, dividers, input outlines, muted text</td>
              </tr>
              <tr>
                <td class="font-semibold">Secondary 600-900</td>
                <td>Dark mode text, footer backgrounds</td>
              </tr>
              <tr>
                <td class="font-semibold">Tertiary 50-200</td>
                <td>Info tints, highlight backgrounds, selected states</td>
              </tr>
              <tr>
                <td class="font-semibold">Tertiary 300-500</td>
                <td>CTA buttons, links, active indicators, badges</td>
              </tr>
              <tr>
                <td class="font-semibold">Tertiary 600-900</td>
                <td>Hover states for CTAs, dark accent sections</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- TYPOGRAPHY -->
      <!-- ============================================================ -->
      <section id="typography" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Typography</h2>

        <div class="space-y-4 mb-8">
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-5xl</span>
            <span class="text-5xl font-bold">Page Title (3rem / 48px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-4xl</span>
            <span class="text-4xl font-bold">Hero Heading (2.25rem / 36px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-3xl</span>
            <span class="text-3xl font-bold">Section Heading (1.875rem / 30px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-2xl</span>
            <span class="text-2xl font-bold">Card Title (1.5rem / 24px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-xl</span>
            <span class="text-xl font-semibold">Subsection (1.25rem / 20px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-lg</span>
            <span class="text-lg">Large body text (1.125rem / 18px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-base</span>
            <span class="text-base">Body text — default (1rem / 16px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-sm</span>
            <span class="text-sm">Secondary text, labels (0.875rem / 14px)</span>
          </div>
          <div class="flex items-baseline gap-4">
            <span class="text-xs font-mono text-base-content/70 w-20 shrink-0">text-xs</span>
            <span class="text-xs">Captions, meta (0.75rem / 12px)</span>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div>
            <h4 class="font-semibold mb-2">Font Weights</h4>
            <p class="font-light">Light (300)</p>
            <p class="font-normal">Normal (400) — body default</p>
            <p class="font-medium">Medium (500)</p>
            <p class="font-semibold">Semibold (600) — subheadings</p>
            <p class="font-bold">Bold (700) — headings</p>
          </div>
          <div>
            <h4 class="font-semibold mb-2">Text Colors</h4>
            <p class="text-base-content">base-content — primary text</p>
            <p class="text-base-content/80">base-content/60 — secondary text</p>
            <p class="text-base-content/70">base-content/40 — muted text</p>
            <p class="text-primary">primary — links, emphasis</p>
            <p class="text-error">error — validation messages</p>
          </div>
          <div>
            <h4 class="font-semibold mb-2">Usage Guidelines</h4>
            <ul class="text-sm space-y-1">
              <li>Page titles: text-3xl font-bold</li>
              <li>Section headings: text-xl font-bold</li>
              <li>Card titles: text-lg font-semibold</li>
              <li>Body: text-base font-normal</li>
              <li>Labels: text-sm text-base-content/80</li>
              <li>Captions: text-xs text-base-content/70</li>
            </ul>
          </div>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- BUTTONS -->
      <!-- ============================================================ -->
      <section id="buttons" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Buttons</h2>

        <h3 class="font-semibold mb-3">Variants</h3>
        <div class="flex flex-wrap gap-3 mb-6">
          <button class="btn btn-primary">Primary</button>
          <button class="btn btn-secondary">Secondary</button>
          <button class="btn btn-accent">Accent</button>
          <button class="btn btn-neutral">Neutral</button>
          <button class="btn btn-info">Info</button>
          <button class="btn btn-success">Success</button>
          <button class="btn btn-warning">Warning</button>
          <button class="btn btn-error">Error</button>
          <button class="btn btn-ghost">Ghost</button>
          <button class="btn btn-outline">Outline</button>
        </div>

        <h3 class="font-semibold mb-3">Sizes</h3>
        <div class="flex flex-wrap items-center gap-3 mb-6">
          <button class="btn btn-primary btn-xs">Extra Small</button>
          <button class="btn btn-primary btn-sm">Small</button>
          <button class="btn btn-primary">Default</button>
          <button class="btn btn-primary btn-lg">Large</button>
        </div>

        <h3 class="font-semibold mb-3">States</h3>
        <div class="flex flex-wrap items-center gap-3 mb-6">
          <button class="btn btn-primary">Normal</button>
          <button class="btn btn-primary" disabled>Disabled</button>
          <button class="btn btn-primary btn-block">Block (full width)</button>
        </div>

        <div class="bg-base-200 rounded-lg p-4 text-sm font-mono">
          <p>Primary action: <code>btn btn-primary</code></p>
          <p>Secondary action: <code>btn btn-outline</code> or <code>btn btn-ghost</code></p>
          <p>Danger: <code>btn btn-error</code> or <code>btn btn-ghost text-error</code></p>
          <p>Small controls: <code>btn btn-sm</code> — tables, cards</p>
          <p>Full width: <code>btn btn-block</code> — mobile forms</p>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- CARDS -->
      <!-- ============================================================ -->
      <section id="cards" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Cards</h2>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h3 class="card-title">Shadow Small</h3>
              <p class="text-sm text-base-content/80">shadow-sm — subtle elevation for list items</p>
            </div>
          </div>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h3 class="card-title">Shadow Default</h3>
              <p class="text-sm text-base-content/80">shadow — standard cards and containers</p>
            </div>
          </div>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h3 class="card-title">Shadow XL</h3>
              <p class="text-sm text-base-content/80">shadow-xl — featured cards, modals</p>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-6">
          <div class="card bg-base-100 shadow border-l-4 border-primary">
            <div class="card-body p-4">
              <h3 class="card-title text-base">Left Border — Primary</h3>
              <p class="text-sm text-base-content/80">
                border-l-4 border-primary — dispatch cards, status indicators
              </p>
            </div>
          </div>
          <div class="card bg-base-100 shadow border-l-4 border-success">
            <div class="card-body p-4">
              <h3 class="card-title text-base">Left Border — Success</h3>
              <p class="text-sm text-base-content/80">
                border-l-4 border-success — active/complete items
              </p>
            </div>
          </div>
        </div>

        <div class="bg-base-200 rounded-lg p-4 text-sm font-mono mt-6">
          <p>Standard card: <code>card bg-base-100 shadow</code></p>
          <p>
            Card body padding: <code>card-body</code>
            (default) or <code>card-body p-4</code>
            (compact)
          </p>
          <p>Status card: <code>card shadow border-l-4 border-[color]</code></p>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- BADGES -->
      <!-- ============================================================ -->
      <section id="badges" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Badges</h2>

        <div class="flex flex-wrap gap-3 mb-6">
          <span class="badge badge-primary">Primary</span>
          <span class="badge badge-secondary">Secondary</span>
          <span class="badge badge-accent">Accent</span>
          <span class="badge badge-ghost">Ghost</span>
          <span class="badge badge-info">Info</span>
          <span class="badge badge-success">Success</span>
          <span class="badge badge-warning">Warning</span>
          <span class="badge badge-error">Error</span>
          <span class="badge badge-outline">Outline</span>
        </div>

        <h3 class="font-semibold mb-3">Sizes</h3>
        <div class="flex flex-wrap items-center gap-3 mb-6">
          <span class="badge badge-primary badge-xs">XS</span>
          <span class="badge badge-primary badge-sm">Small</span>
          <span class="badge badge-primary">Default</span>
          <span class="badge badge-primary badge-lg">Large</span>
        </div>

        <h3 class="font-semibold mb-3">Status Badges (App Convention)</h3>
        <div class="flex flex-wrap gap-3">
          <span class="badge badge-ghost">Pending</span>
          <span class="badge badge-info">Confirmed</span>
          <span class="badge badge-warning">In Progress</span>
          <span class="badge badge-success">Completed</span>
          <span class="badge badge-error">Cancelled</span>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- ALERTS -->
      <!-- ============================================================ -->
      <section id="alerts" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Alerts</h2>

        <div class="space-y-3">
          <div class="alert">
            <span>Default alert — neutral announcements and messages.</span>
          </div>
          <div class="alert alert-info">
            <span>Info — appointment confirmed, subscription active.</span>
          </div>
          <div class="alert alert-success">
            <span>Success — payment complete, wash finished.</span>
          </div>
          <div class="alert alert-warning">
            <span>Warning — unassigned appointments, past-due subscription.</span>
          </div>
          <div class="alert alert-error">
            <span>Error — booking failed, payment declined.</span>
          </div>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- FORMS -->
      <!-- ============================================================ -->
      <section id="forms" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Forms</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
          <div>
            <h3 class="font-semibold mb-3">Text Inputs</h3>
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Default</span></label>
              <input type="text" class="input input-bordered" placeholder="Default input" />
            </div>
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Small</span></label>
              <input type="text" class="input input-bordered input-sm" placeholder="Small input" />
            </div>
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">With error</span></label>
              <input type="text" class="input input-bordered input-error" value="Bad value" />
              <label class="label">
                <span class="label-text-alt text-error">This field is required</span>
              </label>
            </div>
          </div>

          <div>
            <h3 class="font-semibold mb-3">Select & Other Controls</h3>
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Select</span></label>
              <select class="select select-bordered">
                <option>Option A</option>
                <option>Option B</option>
              </select>
            </div>
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Textarea</span></label>
              <textarea class="textarea textarea-bordered" placeholder="Notes..."></textarea>
            </div>
            <div class="form-control mb-3">
              <label class="label cursor-pointer justify-start gap-3">
                <input type="checkbox" class="checkbox checkbox-primary" checked />
                <span class="label-text">Checkbox</span>
              </label>
            </div>
          </div>
        </div>

        <div class="bg-base-200 rounded-lg p-4 text-sm font-mono mt-6">
          <p>Standard input: <code>input input-bordered</code></p>
          <p>Compact: <code>input input-bordered input-sm</code></p>
          <p>Wrap with <code>form-control</code> + <code>label</code> for spacing</p>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- SHADOWS -->
      <!-- ============================================================ -->
      <section id="shadows" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Shadows</h2>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-6">
          <div class="bg-base-100 rounded-lg p-6 text-center" style="box-shadow: var(--shadow-sm)">
            <p class="font-mono text-sm">--shadow-sm</p>
            <p class="text-xs text-base-content/70 mt-1">List items, subtle</p>
          </div>
          <div class="bg-base-100 rounded-lg p-6 text-center" style="box-shadow: var(--shadow-md)">
            <p class="font-mono text-sm">--shadow-md</p>
            <p class="text-xs text-base-content/70 mt-1">Cards, dropdowns</p>
          </div>
          <div class="bg-base-100 rounded-lg p-6 text-center" style="box-shadow: var(--shadow-lg)">
            <p class="font-mono text-sm">--shadow-lg</p>
            <p class="text-xs text-base-content/70 mt-1">Modals, popovers</p>
          </div>
          <div class="bg-base-100 rounded-lg p-6 text-center" style="box-shadow: var(--shadow-xl)">
            <p class="font-mono text-sm">--shadow-xl</p>
            <p class="text-xs text-base-content/70 mt-1">Featured, hero</p>
          </div>
        </div>

        <div class="bg-base-200 rounded-lg p-4 text-sm font-mono mt-6">
          <p>
            Tailwind: <code>shadow-sm</code>, <code>shadow</code>, <code>shadow-lg</code>,
            <code>shadow-xl</code>
          </p>
          <p>Brand shadows use Navy (#1E2A38) at 6-12% opacity for warmth</p>
        </div>
      </section>
      
    <!-- ============================================================ -->
      <!-- SPACING -->
      <!-- ============================================================ -->
      <section id="spacing" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Spacing & Layout</h2>

        <h3 class="font-semibold mb-3">Spacing Scale</h3>
        <div class="space-y-2 mb-8">
          <.spacing_row name="xs" value="0.25rem / 4px" width="w-1" />
          <.spacing_row name="sm" value="0.5rem / 8px" width="w-2" />
          <.spacing_row name="md" value="1rem / 16px" width="w-4" />
          <.spacing_row name="lg" value="1.5rem / 24px" width="w-6" />
          <.spacing_row name="xl" value="2rem / 32px" width="w-8" />
          <.spacing_row name="2xl" value="3rem / 48px" width="w-12" />
          <.spacing_row name="3xl" value="4rem / 64px" width="w-16" />
        </div>

        <h3 class="font-semibold mb-3">Border Radius</h3>
        <div class="flex flex-wrap gap-4 mb-8">
          <div
            class="w-16 h-16 bg-primary/20 border border-primary/40 flex items-center justify-center text-xs"
            style="border-radius: var(--radius-sm)"
          >
            sm
          </div>
          <div
            class="w-16 h-16 bg-primary/20 border border-primary/40 flex items-center justify-center text-xs"
            style="border-radius: var(--radius-md)"
          >
            md
          </div>
          <div
            class="w-16 h-16 bg-primary/20 border border-primary/40 flex items-center justify-center text-xs"
            style="border-radius: var(--radius-lg)"
          >
            lg
          </div>
          <div
            class="w-16 h-16 bg-primary/20 border border-primary/40 flex items-center justify-center text-xs"
            style="border-radius: var(--radius-xl)"
          >
            xl
          </div>
          <div
            class="w-16 h-16 bg-primary/20 border border-primary/40 flex items-center justify-center text-xs"
            style="border-radius: var(--radius-full)"
          >
            full
          </div>
        </div>

        <h3 class="font-semibold mb-3">Layout Guidelines</h3>
        <div class="bg-base-200 rounded-lg p-4 text-sm">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Context</th>
                <th>Max Width</th>
                <th>Padding</th>
                <th>Gap</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Page content</td>
                <td>max-w-7xl (80rem)</td>
                <td>px-4</td>
                <td>-</td>
              </tr>
              <tr>
                <td>Narrow pages (forms, status)</td>
                <td>max-w-lg (32rem)</td>
                <td>px-4</td>
                <td>-</td>
              </tr>
              <tr>
                <td>Card grid</td>
                <td>-</td>
                <td>-</td>
                <td>gap-4 or gap-6</td>
              </tr>
              <tr>
                <td>Card body</td>
                <td>-</td>
                <td>p-4 (compact) or card-body</td>
                <td>-</td>
              </tr>
              <tr>
                <td>Form fields</td>
                <td>-</td>
                <td>-</td>
                <td>mb-3 between fields</td>
              </tr>
              <tr>
                <td>Section spacing</td>
                <td>-</td>
                <td>py-8 or mb-8</td>
                <td>-</td>
              </tr>
              <tr>
                <td>Button groups</td>
                <td>-</td>
                <td>-</td>
                <td>gap-2 or gap-3</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- BUTTON VARIANTS (Plan 1) -->
      <!-- ============================================================ -->
      <section id="button-variants" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Button Variants (new)</h2>
        <div class="space-y-4">
          <div class="flex flex-wrap gap-3 items-center">
            <.button>Primary</.button>
            <.button variant="secondary">Secondary</.button>
            <.button variant="ghost">Ghost</.button>
            <.button variant="destructive">Destructive</.button>
          </div>
          <div class="flex flex-wrap gap-3 items-center">
            <.button size="sm">Small</.button>
            <.button>Medium</.button>
            <.button size="lg">Large</.button>
          </div>
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- STATUS PILLS -->
      <!-- ============================================================ -->
      <section id="status-pills" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Status Pills</h2>
        <div class="flex flex-wrap gap-2 items-center">
          <.status_pill status={:on_target}>On target</.status_pill>
          <.status_pill status={:paid}>Paid</.status_pill>
          <.status_pill status={:underfunded}>Underfunded</.status_pill>
          <.status_pill status={:over}>Over</.status_pill>
          <.status_pill status={:long_term}>Long-term</.status_pill>
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- PROGRESS BARS -->
      <!-- ============================================================ -->
      <section id="progress-bars" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Progress Bars</h2>
        <div class="space-y-2 max-w-sm">
          <.progress_bar value={0.84} />
          <.progress_bar value={0.42} variant={:amber} />
          <.progress_bar value={1.0} variant={:green} />
          <.progress_bar value={0.05} variant={:red} />
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- FLASH MESSAGES (new kinds) -->
      <!-- ============================================================ -->
      <section id="flash-messages" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Flash Messages</h2>
        <p class="text-sm text-base-content/70 mb-4">All four kinds (info / success / warning / error). They normally render as toasts in the corner — here they stack inline for review.</p>
        <div class="space-y-2 relative">
          <.flash kind={:info}>Info — your changes were saved.</.flash>
          <.flash kind={:success}>Success — booking confirmed.</.flash>
          <.flash kind={:warning}>Warning — tax reserve is underfunded.</.flash>
          <.flash kind={:error}>Error — payment failed.</.flash>
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- EMPTY STATE -->
      <!-- ============================================================ -->
      <section id="empty-state" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Empty State</h2>
        <div class="bg-base-100 border border-base-300 rounded-box max-w-md">
          <.empty_state
            icon="hero-calendar"
            title="No appointments yet"
            body="Book your first wash to see it here."
          >
            <:action>
              <.button>Book now</.button>
            </:action>
          </.empty_state>
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- KPI CARD -->
      <!-- ============================================================ -->
      <section id="kpi-card" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">KPI Card</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 max-w-3xl">
          <.kpi_card
            label="Cash on hand"
            value="$24,807"
            delta="+12.4%"
            delta_direction={:up}
            subtext="vs $22,067 last month"
          />
          <.kpi_card
            label="Active subscribers"
            value="142"
            delta="-3"
            delta_direction={:down}
            subtext="vs 145 last week"
          />
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- BUCKET CARDS -->
      <!-- ============================================================ -->
      <section id="bucket-cards" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Bucket Cards</h2>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
          <.bucket_card label="Operating" amount="$8,420" target="of $10,000 goal" target_pct={0.84} status={:on_target} status_label="On target" />
          <.bucket_card label="Tax reserve" amount="$3,150" target="of $5,000 goal" target_pct={0.63} status={:underfunded} status_label="Underfunded" />
          <.bucket_card label="Savings" amount="$10,200" target="of $15,000 goal" target_pct={0.68} status={:on_target} status_label="68% goal" />
          <.bucket_card label="Investment" amount="$0" target="no goal set" status={:long_term} status_label="Long-term" />
          <.bucket_card label="Salary" amount="$3,037" target="paid Apr 1" target_pct={1.0} status={:paid} status_label="Paid" />
        </div>
      </section>

      <!-- ============================================================ -->
      <!-- MODAL -->
      <!-- ============================================================ -->
      <section id="modal" class="mb-16">
        <h2 class="text-2xl font-bold mb-6 border-b border-base-300 pb-2">Modal</h2>
        <p class="text-sm text-base-content/70 mb-4">Click to open. Backdrop click or Cancel closes.</p>
        <.button phx-click="toggle_demo_modal">Open demo modal</.button>
        <.modal id="demo-modal" show={@demo_modal_open}>
          <:title>Confirm action</:title>
          This is what a modal looks like in the new design system.
          <:footer>
            <.button variant="ghost" phx-click="toggle_demo_modal">Cancel</.button>
            <.button variant="primary" phx-click="toggle_demo_modal">Confirm</.button>
          </:footer>
        </.modal>
      </section>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_demo_modal", _params, socket) do
    {:noreply, update(socket, :demo_modal_open, &(!&1))}
  end

  # --- Components ---

  attr :hex, :string, required: true
  attr :label, :string, required: true
  attr :dark, :boolean, default: false
  attr :border, :boolean, default: false
  attr :prefix, :string, default: ""

  defp swatch(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <div
        class={["w-full aspect-square rounded-lg", @border && "border border-base-300"]}
        style={"background-color: #{@hex}"}
      />
      <span class="text-xs font-mono text-base-content/80">{@label}</span>
      <span class="text-[10px] font-mono text-base-content/70">{@hex}</span>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :width, :string, required: true

  defp spacing_row(assigns) do
    ~H"""
    <div class="flex items-center gap-4">
      <span class="text-xs font-mono text-base-content/70 w-12">{@name}</span>
      <div class={["h-4 bg-primary/30 rounded", @width]} />
      <span class="text-xs text-base-content/80">{@value}</span>
    </div>
    """
  end
end
