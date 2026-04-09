import { Outlet, Link, useNavigate } from 'react-router-dom'
export default function App() {
  const nav = useNavigate()
  const logged = !!localStorage.getItem('token')
  return (
    <div className="app">
      <header>
        <h1>Dr. Samuel</h1>
        <nav>
          {logged
            ? <button onClick={() => { localStorage.removeItem('token'); nav('/login') }}>Logout</button>
            : <Link to="/login">Login</Link>}
        </nav>
      </header>
      <main><Outlet /></main>
    </div>
  )
}
