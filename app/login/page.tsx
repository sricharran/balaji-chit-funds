import { signIn } from "./actions";

const messages: Record<string, string> = {
  missing: "Enter your email and password to continue.",
  invalid: "Supabase did not accept this email and password. Confirm the user exists under Supabase → Authentication → Users, then check the password. The anon key is only for connecting the app; it is not a login credential.",
  unconfirmed: "This Supabase user needs email confirmation. Confirm the account in Supabase Authentication, or enable email auto-confirm for your development project.",
  connection: "The app could not reach Supabase Auth. Check the project URL, anon key, network access, and restart the Next.js server after changing .env.",
  unauthorized: "Supabase signed you in, but this user has no active owner/staff profile. Apply the migrations and run the owner profile setup SQL in README.md.",
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return <main className="auth-screen">
    <section className="auth-brand">
      <div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.75}}>CHIT FUNDS</span></span></div>
      <div className="brand-copy"><div className="brand-kicker">A clearer way to manage every group</div><h1>Confidence in every collection.</h1><p>Your groups, auctions and member accounts — together in one secure place.</p></div>
      <div className="brand-bottom">Private workspace · Secure access</div>
    </section>
    <section className="auth-main"><div className="auth-card">
      <div className="eyebrow">WELCOME BACK</div><h2>Sign in to your account</h2><p className="auth-subtitle">Use your business account to continue to the management dashboard.</p>
      {error && messages[error] && <div className="form-error" role="alert">{messages[error]}</div>}
      <form action={signIn}>
        <div className="field"><label htmlFor="email">Email address</label><input id="email" name="email" type="email" autoComplete="username" placeholder="you@balajichitfunds.com" required /></div>
        <div className="field"><label htmlFor="password">Password</label><input id="password" name="password" type="password" autoComplete="current-password" placeholder="Enter your password" required /></div>
        <button className="primary-button" type="submit">Sign in securely</button>
      </form>
      <p className="auth-footnote">Access is limited to authorized business users. Contact your administrator if you need an account.</p>
    </div></section>
  </main>;
}
