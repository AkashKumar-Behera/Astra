package com.astra.always

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader
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
            val name = widgetData.getString("friend_name", "Partner") ?: "Partner"
            views.setTextViewText(R.id.widget_friend_name, name)

            // Distance
            val distance = widgetData.getString("friend_distance", "-- km") ?: "-- km"
            views.setTextViewText(R.id.widget_friend_distance, "⚡ $distance")

            // Status / Freshness
            val status = widgetData.getString("friend_status", "Astra Live") ?: "Astra Live"
            views.setTextViewText(R.id.widget_friend_status, status)

            // Battery
            val battery = widgetData.getString("friend_battery", "🔋 --%") ?: "🔋 --%"
            views.setTextViewText(R.id.widget_friend_battery_text, battery)

            // Avatar initial fallback
            val initial = if (name.isNotBlank()) name.first().uppercase() else "✦"
            views.setTextViewText(R.id.widget_avatar_initial, initial)

            // Circular Avatar Image if available locally
            val photoPath = widgetData.getString("friend_photo_path", null)
            bindCircularAvatar(views, R.id.widget_avatar_image, R.id.widget_avatar_initial, photoPath)

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

    companion object {
        fun bindCircularAvatar(
            views: RemoteViews,
            imageViewId: Int,
            initialViewId: Int,
            photoPath: String?
        ) {
            if (!photoPath.isNullOrEmpty()) {
                val file = File(photoPath)
                if (file.exists()) {
                    try {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        if (bitmap != null) {
                            val circularBitmap = toCircularBitmap(bitmap)
                            views.setImageViewBitmap(imageViewId, circularBitmap)
                            views.setViewVisibility(imageViewId, View.VISIBLE)
                            views.setViewVisibility(initialViewId, View.GONE)
                            return
                        }
                    } catch (_: Exception) {}
                }
            }
            views.setViewVisibility(imageViewId, View.GONE)
            views.setViewVisibility(initialViewId, View.VISIBLE)
        }

        fun toCircularBitmap(bitmap: Bitmap): Bitmap {
            val size = Math.min(bitmap.width, bitmap.height)
            val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val shader = BitmapShader(
                Bitmap.createScaledBitmap(bitmap, size, size, false),
                Shader.TileMode.CLAMP,
                Shader.TileMode.CLAMP
            )
            paint.shader = shader
            val radius = size / 2f
            canvas.drawCircle(radius, radius, radius, paint)
            return output
        }
    }
}
