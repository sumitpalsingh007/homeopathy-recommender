import axios from 'axios'
import AsyncStorage from '@react-native-async-storage/async-storage'
import Constants from 'expo-constants'

export const api = axios.create({
  baseURL: Constants.expoConfig?.extra?.apiBase || 'http://10.0.2.2:8080/api'
})

api.interceptors.request.use(async cfg => {
  const t = await AsyncStorage.getItem('token')
  if (t) cfg.headers.Authorization = `Bearer ${t}`
  return cfg
})
