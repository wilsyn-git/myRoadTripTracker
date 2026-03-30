# IMPORTANT: Add Location Permission to Info.plist

You need to add the following key to your Info.plist file:

Key: `Privacy - Location When In Use Usage Description`
Value: "We need your location to record where you spotted license plates during your road trip."

In Xcode:
1. Click on your project in the navigator
2. Select your app target
3. Go to the "Info" tab
4. Click the "+" button to add a new key
5. Type "Privacy - Location When In Use Usage Description"
6. Set the value to the description above

Alternatively, if editing Info.plist as source code:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to record where you spotted license plates during your road trip.</string>
```

Without this, the app will crash when trying to request location permissions!
