import { useState } from 'react'
import { api } from './api'
import { useNavigate } from 'react-router-dom'

export default function Login() {
  const [mode, setMode] = useState('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [err, setErr] = useState(null)
  const nav = useNavigate()

  async function submit(e) {
    e.preventDefault()
    try {
      const { data } = await api.post(`/auth/${mode}`, { email, password })
      localStorage.setItem('token', data.token)
      nav('/chat')
    } catch (e) { setErr(e.response?.data?.error || 'failed') }
  }

  return (
    <form onSubmit={submit} className="card">
      <h2>{mode === 'login' ? 'Login' : 'Sign up'}</h2>
      <input value={email} onChange={e=>setEmail(e.target.value)} placeholder="email" />
      <input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="password" />
      <button type="submit">{mode}</button>
      <a onClick={()=>setMode(mode==='login'?'signup':'login')}>
        {mode==='login' ? 'Need an account?' : 'Have an account?'}
      </a>
      {err && <p className="err">{err}</p>}
    </form>
  )
}
