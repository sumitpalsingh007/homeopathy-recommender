import React, { useState } from 'react'
import { View, Text, TextInput, Button, StyleSheet, Alert } from 'react-native'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { api } from './api'

export default function LoginScreen({ navigation }) {
  const [mode, setMode] = useState('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')

  async function submit() {
    try {
      const { data } = await api.post(`/auth/${mode}`, { email, password })
      await AsyncStorage.setItem('token', data.token)
      navigation.replace('Chat')
    } catch (e) { Alert.alert('Error', e.response?.data?.error || e.message) }
  }

  return (
    <View style={styles.c}>
      <Text style={styles.h}>{mode === 'login' ? 'Login' : 'Sign up'}</Text>
      <TextInput style={styles.in} placeholder="email" value={email} onChangeText={setEmail} autoCapitalize="none" />
      <TextInput style={styles.in} placeholder="password" value={password} onChangeText={setPassword} secureTextEntry />
      <Button title={mode} onPress={submit} />
      <Text style={styles.link} onPress={()=>setMode(mode==='login'?'signup':'login')}>
        {mode==='login' ? 'Need an account?' : 'Have an account?'}
      </Text>
    </View>
  )
}

const styles = StyleSheet.create({
  c: { padding: 24, flex: 1, justifyContent: 'center' },
  h: { fontSize: 28, marginBottom: 16 },
  in: { borderWidth: 1, borderColor: '#ccc', borderRadius: 6, padding: 10, marginBottom: 12 },
  link: { color: '#3b6', marginTop: 16, textAlign: 'center' }
})
