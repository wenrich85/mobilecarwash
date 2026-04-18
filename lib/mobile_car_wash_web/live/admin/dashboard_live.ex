defmodule MobileCarWashWeb.Admin.DashboardLive do
  @moduledoc """
  Admin hub. Single landing page at /admin with cards for every management
  area. Replaces the old dropdown nav so every function is visible at a glance.
  """
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Admin Hub",
       sections: sections()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="mb-8">
        <h1 class="text-4xl font-bold mb-2">Admin Hub</h1>
        <p class="text-base-content/60">
          Everything you need to run the business. Each card opens a dedicated page.
        </p>
      </div>

      <div :for={section <- @sections} class="mb-10">
        <div class="flex items-baseline gap-3 mb-4">
          <h2 class="text-xl font-bold">{section.title}</h2>
          <span class="text-sm text-base-content/50">{section.subtitle}</span>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <.link
            :for={card <- section.cards}
            navigate={card.path}
            class="card bg-base-100 shadow hover:shadow-lg transition-all hover:-translate-y-0.5 border border-base-200"
          >
            <div class="card-body p-5">
              <div class="flex items-start gap-3">
                <div class="text-3xl leading-none">{card.icon}</div>
                <div class="flex-1">
                  <h3 class="font-bold text-lg mb-1">{card.title}</h3>
                  <p class="text-sm text-base-content/60">{card.description}</p>
                </div>
              </div>
            </div>
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # --- card registry ---

  defp sections do
    [
      %{
        title: "Operations",
        subtitle: "Day-to-day running of the business",
        cards: [
          %{
            icon: "🚐",
            title: "Dispatch",
            description: "Today's wash queue. Assign techs, monitor progress, handle live updates.",
            path: "/admin/dispatch"
          },
          %{
            icon: "📆",
            title: "Appointment Blocks",
            description: "Upcoming booking windows. Optimize routes, adjust closing times, cancel if needed.",
            path: "/admin/blocks"
          },
          %{
            icon: "🗓️",
            title: "Schedule Templates",
            description: "Weekly recurring slots that drive block generation. Add or deactivate windows.",
            path: "/admin/schedule-templates"
          }
        ]
      },
      %{
        title: "Team",
        subtitle: "People and equipment",
        cards: [
          %{
            icon: "👷",
            title: "Technicians",
            description: "View and manage your wash technicians, their zones, and pay rates.",
            path: "/admin/technicians"
          },
          %{
            icon: "🚚",
            title: "Vans",
            description: "Service vehicles. License plates, active status, assignments.",
            path: "/admin/vans"
          },
          %{
            icon: "🧭",
            title: "Org Chart",
            description: "Business structure and reporting lines. Position definitions.",
            path: "/admin/org-chart"
          }
        ]
      },
      %{
        title: "Finances",
        subtitle: "Money in, money out, money saved",
        cards: [
          %{
            icon: "💰",
            title: "Cash Flow",
            description: "Five-bucket money system with animated transfers. Track deposits and expenses.",
            path: "/admin/cash-flow"
          },
          %{
            icon: "📊",
            title: "Metrics",
            description: "Revenue, customer funnel (AARRR), retention. Auto-refreshing dashboard.",
            path: "/admin/metrics"
          }
        ]
      },
      %{
        title: "Catalog & Inventory",
        subtitle: "What you sell and what you use",
        cards: [
          %{
            icon: "🧾",
            title: "Services & Plans",
            description: "Edit service menu, prices, subscription tiers, and blocked dates.",
            path: "/admin/settings"
          },
          %{
            icon: "🧴",
            title: "Supplies",
            description: "Chemicals, towels, equipment. Track stock and log restocks.",
            path: "/admin/supplies"
          },
          %{
            icon: "📋",
            title: "Procedures (SOPs)",
            description: "Step-by-step wash procedures. Your standard operating guide.",
            path: "/admin/procedures"
          }
        ]
      },
      %{
        title: "Business Tools",
        subtitle: "Compliance, analytics, and design",
        cards: [
          %{
            icon: "🏛️",
            title: "Business Formation",
            description: "Texas, federal, and veteran compliance checklist. Filings and renewals.",
            path: "/admin/formation"
          },
          %{
            icon: "📈",
            title: "Event Log",
            description: "Analytics events by customers and tech. Useful for debugging flows.",
            path: "/admin/events"
          },
          %{
            icon: "🎨",
            title: "Style Guide",
            description: "Component library reference — colors, typography, cards, buttons.",
            path: "/style-guide"
          }
        ]
      }
    ]
  end
end
