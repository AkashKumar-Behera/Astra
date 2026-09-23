package com.astra.always

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PartnerStatusWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.partner_status_widget)

            // Friend Name
            val name = widgetData.getString("friend_name", "Partner") ?: "Partner"
            views.setTextViewText(R.id.widget_status_friend_name, name)

            // Distance
            val distance = widgetData.getString("friend_distance", "-- km") ?: "-- km"
            views.setTextViewText(R.id.widget_status_distance, "⚡ $distance")

            // Last Seen / Status
            val status = widgetData.getString("friend_status", "Astra Live • Connected") ?: "Astra Live • Connected"
            views.setTextViewText(R.id.widget_status_last_seen, status)

            // Battery
            val battery = widgetData.getString("friend_battery", "🔋 --%") ?: "🔋 --%"
            views.setTextViewText(R.id.widget_status_battery, battery)

            // Network
            val network = widgetData.getString("friend_network", "📶 Live") ?: "📶 Live"
            views.setTextViewText(R.id.widget_status_network, network)

            // Avatar initial fallback
            val initial = if (name.isNotBlank()) name.first().uppercase() else "✦"
            views.setTextViewText(R.id.widget_status_avatar_initial, initial)

            // Circular Avatar Image if available locally
            val photoPath = widgetData.getString("friend_photo_path", null)
            FriendDistanceWidgetProvider.bindCircularAvatar(
                views,
                R.id.widget_status_avatar_image,
                R.id.widget_status_avatar_initial,
                photoPath
            )

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
            views.setOnClickPendingIntent(R.id.widget_status_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
