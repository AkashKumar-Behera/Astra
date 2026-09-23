package com.astra.always

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class FriendDistanceWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.friend_distance_widget)

            // Friend Name
            val name = widgetData.getString("friend_name", "Friend") ?: "Friend"
            views.setTextViewText(R.id.widget_friend_name, name)

            // Distance
            val distance = widgetData.getString("friend_distance", "-- km") ?: "-- km"
            views.setTextViewText(R.id.widget_friend_distance, distance)

            // Status / Freshness
            val status = widgetData.getString("friend_status", "Astra Live") ?: "Astra Live"
            views.setTextViewText(R.id.widget_friend_status, status)

            // Avatar initial fallback
            val initial = if (name.isNotBlank()) name.first().uppercase() else "A"
            views.setTextViewText(R.id.widget_avatar_initial, initial)

            // Avatar Image if available locally
            val photoPath = widgetData.getString("friend_photo_path", null)
            if (!photoPath.isNullOrEmpty()) {
                val file = File(photoPath)
                if (file.exists()) {
                    try {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        if (bitmap != null) {
                            views.setImageViewBitmap(R.id.widget_avatar_image, bitmap)
                            views.setViewVisibility(R.id.widget_avatar_image, View.VISIBLE)
                            views.setViewVisibility(R.id.widget_avatar_initial, View.GONE)
                        } else {
                            views.setViewVisibility(R.id.widget_avatar_image, View.GONE)
                            views.setViewVisibility(R.id.widget_avatar_initial, View.VISIBLE)
                        }
                    } catch (_: Exception) {
                        views.setViewVisibility(R.id.widget_avatar_image, View.GONE)
                        views.setViewVisibility(R.id.widget_avatar_initial, View.VISIBLE)
                    }
                } else {
                    views.setViewVisibility(R.id.widget_avatar_image, View.GONE)
                    views.setViewVisibility(R.id.widget_avatar_initial, View.VISIBLE)
                }
            } else {
                views.setViewVisibility(R.id.widget_avatar_image, View.GONE)
                views.setViewVisibility(R.id.widget_avatar_initial, View.VISIBLE)
            }

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
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
