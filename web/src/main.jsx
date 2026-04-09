import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import App from './App.jsx'
import Login from './Login.jsx'
import Chat from './Chat.jsx'
import './styles.css'

function Protected({ children }) {
  return localStorage.getItem('token') ? children : <Navigate to="/login" />
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <BrowserRouter>
    <Routes>
      <Route path="/" element={<App />}>
        <Route index element={<Navigate to="/chat" />} />
        <Route path="login" element={<Login />} />
        <Route path="chat" element={<Protected><Chat /></Protected>} />
      </Route>
    </Routes>
  </BrowserRouter>
)
