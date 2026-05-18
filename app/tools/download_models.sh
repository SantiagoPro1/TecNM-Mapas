#!/bin/bash

# Define el directorio de destino relativo a la raíz del proyecto Flutter
DEST_DIR="assets/models"

echo "🚀 Iniciando descarga de modelos TFLite para NAVIA..."

# 1. Crear el directorio si no existe
mkdir -p "$DEST_DIR"
echo "📁 Directorio asegurado: $DEST_DIR"

# 2. Descargar modelo de detección de obstáculos (EfficientDet-Lite0)
echo "⬇️ Descargando obstacles_detector.tflite (EfficientDet-Lite0)..."
curl -L "https://tfhub.dev/tensorflow/lite-model/efficientdet/lite0/detection/default/1?lite-format=tflite" \
     -o "$DEST_DIR/obstacles_detector.tflite"

# 3. Descargar las etiquetas COCO
echo "⬇️ Descargando coco_labels.txt..."
curl -L "https://raw.githubusercontent.com/tensorflow/models/master/research/object_detection/data/mscoco_label_map.pbtxt" \
     -o "$DEST_DIR/coco_labels.txt"

# 4. Placeholder para el modelo de marcadores personalizados
echo "⚠️ NOTA: El modelo de marcadores (campus_markers.tflite) debe colocarse manualmente una vez entrenado."
# curl -L "https://firebasestorage.googleapis.com/v0/b/sinait-colima.firebasestorage.app/o/models%2Fobstacles_detector.tflite?alt=media&token=bc1081bd-f110-4fed-9074-c7b92d07f7d7" -o "$DEST_DIR/campus_markers.tflite"

echo "✅ ¡Proceso completado! Los archivos están listos en $DEST_DIR."