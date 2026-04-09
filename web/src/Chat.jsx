import { useState, useRef, useEffect } from 'react'
import { api } from './api'

export default function Chat() {
  const [messages, setMessages] = useState([
    { role: 'assistant', content: "Hello, I'm Dr. Samuel. What brings you in today?" }
  ])
  const [input, setInput] = useState('')
  const [sessionId, setSessionId] = useState(null)
  const [busy, setBusy] = useState(false)
  const endRef = useRef(null)

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  async function send() {
    if (!input.trim() || busy) return
    const userMsg = { role: 'user', content: input }
    setMessages(m => [...m, userMsg])
    setInput('')
    setBusy(true)
    try {
      const { data } = await api.post('/chat', { message: userMsg.content, sessionId })
      setSessionId(data.sessionId)
      setMessages(m => [...m, { role: 'assistant', content: data.reply }])
    } catch (e) {
      setMessages(m => [...m, { role: 'assistant', content: '⚠️ ' + (e.message || 'error') }])
    } finally { setBusy(false) }
  }

  return (
    <div className="chat">
      <div className="messages">
        {messages.map((m, i) => (
          <div key={i} className={`msg ${m.role}`}>{m.content}</div>
        ))}
        <div ref={endRef} />
      </div>
      <div className="composer">
        <input
          value={input}
          onChange={e=>setInput(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && send()}
          placeholder="Describe your symptoms..."
          disabled={busy}
        />
        <button onClick={send} disabled={busy}>{busy ? '...' : 'Send'}</button>
      </div>
    </div>
  )
}
