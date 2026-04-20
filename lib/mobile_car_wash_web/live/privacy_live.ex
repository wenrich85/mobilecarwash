defmodule MobileCarWashWeb.PrivacyLive do
  use MobileCarWashWeb, :live_view

  @effective_date "April 18, 2026"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Privacy Policy",
       canonical_path: "/privacy",
       meta_description:
         "Privacy Policy for Driveway Detail Co — what we collect, how we use it, and the processors we rely on.",
       effective_date: @effective_date
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article class="max-w-3xl mx-auto px-4 py-12 prose prose-slate">
      <h1>Privacy Policy</h1>
      <p class="text-base-content/80">Effective {@effective_date}</p>

      <p>
        Driveway Detail Co ("we", "us") operates the website at drivewaydetailcosa.com and
        provides mobile car wash and detailing services. This policy explains what information
        we collect, why we collect it, and who processes it on our behalf.
      </p>

      <h2>Information we collect</h2>
      <ul>
        <li>
          <strong>Account & booking details:</strong>
          name, email address, phone number, service address, and vehicle information you
          provide when you create an account or book a wash.
        </li>
        <li>
          <strong>Payment information:</strong>
          payments are processed by <strong>Stripe</strong>. We do not store full card numbers
          on our servers — Stripe handles card data under PCI-DSS.
        </li>
        <li>
          <strong>Service records:</strong>
          appointment history, photos taken during service (for quality assurance), and
          technician notes.
        </li>
        <li>
          <strong>Analytics & site usage:</strong>
          we use <strong>Google Analytics</strong>
          (GA4) to understand how visitors use the site.
          GA4 sets cookies and collects information such as pages viewed, approximate location
          (city-level), device type, and referring source.
        </li>
        <li>
          <strong>Logs & security data:</strong>
          standard server logs including IP address and user agent, retained for security and
          troubleshooting.
        </li>
      </ul>

      <h2>How we use your information</h2>
      <ul>
        <li>To schedule, dispatch, and complete the services you book.</li>
        <li>To send booking confirmations, reminders, and receipts by email and SMS.</li>
        <li>To process payments and manage subscriptions.</li>
        <li>To improve the site, fix issues, and prevent abuse.</li>
      </ul>

      <h2>Service providers</h2>
      <p>
        We share limited information with the following processors so they can perform services on our behalf:
      </p>
      <ul>
        <li><strong>Stripe</strong> — payment processing.</li>
        <li>
          <strong>Twilio</strong> — SMS notifications (confirmations, reminders, technician updates).
        </li>
        <li><strong>Google Analytics</strong> — site analytics.</li>
        <li><strong>DigitalOcean</strong> — hosting and infrastructure.</li>
      </ul>
      <p>
        We do not sell your personal information, and we do not share it with third parties for
        their own marketing.
      </p>

      <h2>SMS messages</h2>
      <p>
        When you book with us, you consent to receive transactional SMS messages (booking
        confirmation, appointment reminders, technician-on-the-way notices, and post-wash
        review requests). Message and data rates may apply. Reply <strong>STOP</strong>
        to any message to opt out; reply <strong>HELP</strong>
        for help.
      </p>

      <h2>Cookies and tracking</h2>
      <p>
        We use cookies for essential site functionality (session, CSRF protection) and for
        Google Analytics. You can disable cookies in your browser, install the <a
          href="https://tools.google.com/dlpage/gaoptout"
          rel="noopener"
        >Google Analytics opt-out add-on</a>,
        or enable your browser's Do Not Track / Global Privacy Control signal.
      </p>

      <h2>Data retention</h2>
      <p>
        We keep account and service records for as long as your account is active and for a
        reasonable period afterward to meet tax, accounting, and dispute-resolution
        obligations. Analytics data is retained according to the default GA4 retention setting.
      </p>

      <h2>Your rights</h2>
      <p>You can:</p>
      <ul>
        <li>Request a copy of the personal information we hold about you.</li>
        <li>Ask us to correct or delete your account information.</li>
        <li>Opt out of SMS (reply STOP) and marketing email at any time.</li>
      </ul>
      <p>
        To exercise any of these rights, email us at the address below. We will respond within
        a reasonable time frame.
      </p>

      <h2>Children</h2>
      <p>
        Our services are not directed to children under 13, and we do not knowingly collect
        personal information from them.
      </p>

      <h2>Changes to this policy</h2>
      <p>
        If we make material changes, we will update the effective date above and, where
        appropriate, notify you by email.
      </p>

      <h2>Contact</h2>
      <p>
        Questions or requests? Email <a href="mailto:hello@drivewaydetailcosa.com">hello@drivewaydetailcosa.com</a>.
      </p>

      <p class="mt-10">
        <.link navigate={~p"/"} class="btn btn-ghost">← Back to home</.link>
      </p>
    </article>
    """
  end
end
