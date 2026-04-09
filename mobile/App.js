import React from 'react'
import { NavigationContainer } from '@react-navigation/native'
import { createNativeStackNavigator } from '@react-navigation/native-stack'
import LoginScreen from './src/LoginScreen'
import ChatScreen from './src/ChatScreen'

const Stack = createNativeStackNavigator()

export default function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator initialRouteName="Login">
        <Stack.Screen name="Login" component={LoginScreen} options={{ title: 'Dr. Samuel' }} />
        <Stack.Screen name="Chat" component={ChatScreen} options={{ title: 'Consultation' }} />
      </Stack.Navigator>
    </NavigationContainer>
  )
}
