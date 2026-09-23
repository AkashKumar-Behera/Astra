package com.astra.always

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PairOrbitWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pair_orbit_widget)

            // --- User (Self) Info ---
            val myName = widgetData.getString("my_name", "You") ?: "You"
            views.setTextViewText(R.id.widget_my_name, myName)

            val myBattery = widgetData.getString("my_battery", "🔋 --%") ?: "🔋 --%"
            views.setTextViewText(R.id.widget_my_battery, myBattery)

            val myInitial = if (myName.isNotBlank()) myName.first().uppercase() else "ME"
            views.setTextViewText(R.id.widget_my_avatar_initial, myInitial)

            val myPhotoPath = widgetData.getString("my_photo_path", null)
            FriendDistanceWidgetProvider.bindCircularAvatar(
                views,
                R.id.widget_my_avatar_image,
                R.id.widget_my_avatar_initial,
                myPhotoPath
            )

            // --- Partner Info ---
            val friendName = widgetData.getString("friend_name", "Partner") ?: "Partner"
            views.setTextViewText(R.id.widget_partner_name, friendName)

            val friendBattery = widgetData.getString("friend_battery", "🔋 --%") ?: "🔋 --%"
            views.setTextViewText(R.id.widget_partner_battery, friendBattery)

            val friendInitial = if (friendName.isNotBlank()) friendName.first().uppercase() else "✦"
            views.setTextViewText(R.id.widget_partner_avatar_initial, friendInitial)

            val friendPhotoPath = widgetData.getString("friend_photo_path", null)
            FriendDistanceWidgetProvider.bindCircularAvatar(
                views,
                R.id.widget_partner_avatar_image,
                R.id.widget_partner_avatar_initial,
                friendPhotoPath
            )

            // --- Distance Bridge ---
            val distance = widgetData.getString("friend_distance", "-- km") ?: "-- km"
            views.setTextViewText(R.id.widget_orbit_distance, "⚡ $distance")

            // Status
            val status = widgetData.getString("friend_status", "Astra Duo • Live Connected") ?: "Astra Duo • Live Connected"
            views.setTextViewText(R.id.widget_orbit_status, status)

            // Click Intent to open MainActivity
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_orbit_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
