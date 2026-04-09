import React, { useState, useRef, useEffect } from 'react'
import { View, Text, TextInput, FlatList, TouchableOpacity, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native'
import { api } from './api'

export default function ChatScreen() {
  const [messages, setMessages] = useState([
    { role: 'assistant', content: "Hello, I'm Dr. Samuel. What brings you in today?" }
  ])
  const [input, setInput] = useState('')
  const [sessionId, setSessionId] = useState(null)
  const [busy, setBusy] = useState(false)
  const listRef = useRef(null)

  useEffect(() => { listRef.current?.scrollToEnd({ animated: true }) }, [messages])

  async function send() {
    if (!input.trim() || busy) return
    const msg = { role: 'user', content: input }
    setMessages(m => [...m, msg])
    setInput('')
    setBusy(true)
    try {
      const { data } = await api.post('/chat', { message: msg.content, sessionId })
      setSessionId(data.sessionId)
      setMessages(m => [...m, { role: 'assistant', content: data.reply }])
    } catch (e) {
      setMessages(m => [...m, { role: 'assistant', content: '⚠️ ' + e.message }])
    } finally { setBusy(false) }
  }

  return (
    <KeyboardAvoidingView style={styles.c} behavior={Platform.OS==='ios'?'padding':undefined}>
      <FlatList
        ref={listRef}
        data={messages}
        keyExtractor={(_, i) => String(i)}
        renderItem={({ item }) => (
          <View style={[styles.bubble, item.role==='user'?styles.user:styles.bot]}>
            <Text>{item.content}</Text>
          </View>
        )}
      />
      <View style={styles.composer}>
        <TextInput style={styles.input} value={input} onChangeText={setInput}
          placeholder="Describe your symptoms..." editable={!busy} />
        <TouchableOpacity style={styles.send} onPress={send} disabled={busy}>
          <Text style={{color:'#fff'}}>{busy?'...':'Send'}</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  )
}

const styles = StyleSheet.create({
  c: { flex: 1, padding: 12 },
  bubble: { padding: 10, borderRadius: 12, marginVertical: 4, maxWidth: '80%' },
  user: { alignSelf: 'flex-end', backgroundColor: '#dfeeff' },
  bot: { alignSelf: 'flex-start', backgroundColor: '#f0f0f0' },
  composer: { flexDirection: 'row', marginTop: 8 },
  input: { flex: 1, borderWidth: 1, borderColor: '#ccc', borderRadius: 8, padding: 10 },
  send: { backgroundColor: '#3b6', paddingHorizontal: 18, justifyContent: 'center', borderRadius: 8, marginLeft: 8 }
})
