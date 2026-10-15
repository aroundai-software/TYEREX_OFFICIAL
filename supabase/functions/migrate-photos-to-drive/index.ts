import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { google } from 'https://esm.sh/googleapis@126'

const serviceAccountKeyStr = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_KEY')
const rawDriveFolderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID')
const clientId = Deno.env.get('GOOGLE_CLIENT_ID')
const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET')
const refreshToken = Deno.env.get('GOOGLE_REFRESH_TOKEN')

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase URL or Key not found in environment.')
    }
    
    if (!rawDriveFolderId) {
      throw new Error('GOOGLE_DRIVE_FOLDER_ID is missing in Supabase secrets.')
    }
    
    const driveFolderId = rawDriveFolderId.trim().replace(/[^a-zA-Z0-9_-]/g, '')
    const supabase = createClient(supabaseUrl, supabaseKey)
    let accessToken = ''

    // 1. Authenticate using OAuth Refresh Token (Uses 5 TB Account)
    if (clientId && clientSecret && refreshToken) {
      const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: clientId.trim(),
          client_secret: clientSecret.trim(),
          refresh_token: refreshToken.trim(),
          grant_type: 'refresh_token',
        })
      })
      const tokenData = await tokenRes.json()
      accessToken = tokenData.access_token
      if (!accessToken) {
        throw new Error('Failed to refresh Google OAuth token: ' + JSON.stringify(tokenData))
      }
      console.log('Authenticated using Google OAuth (5 TB Storage Quota active)')
    } 
    // 2. Fallback to Service Account Key
    else if (serviceAccountKeyStr) {
      const serviceAccount = JSON.parse(serviceAccountKeyStr)
      const jwtClient = new google.auth.JWT(
        serviceAccount.client_email,
        null,
        serviceAccount.private_key.replace(/\\n/g, '\n'),
        ['https://www.googleapis.com/auth/drive']
      )
      const tokenInfo = await jwtClient.authorize()
      accessToken = tokenInfo.access_token || jwtClient.credentials.access_token
      if (!accessToken) {
        throw new Error('Failed to authenticate Service Account')
      }
      console.log('Authenticated using Service Account Key')
    } else {
      throw new Error('No Google credentials found in secrets.')
    }

    // 0 threshold for immediate migration of all completed jobs
    const thresholdMs = 0
    const thresholdDate = new Date().toISOString()

    // Extract current Supabase project reference
    const currentProjectRef = supabaseUrl.replace(/^https?:\/\//, '').split('.')[0] // 'xlgeqjpdsimkskssikhb'

    console.log(`Checking for completed reports with photos in current project (${currentProjectRef})...`)

    // Query completed reports containing unmigrated photos in current project
    const { data: allWithPhotos, error } = await supabase
      .from('reports')
      .select('id, vehicle_id, job_card_id, client_phone, photo_urls, after_photo_urls, status, completed_at, created_at, gdrive_folder_url')
      .eq('status', 'Completed')
      .is('gdrive_folder_url', null)
      .not('photo_urls', 'is', null)
      .order('id', { ascending: false })
      .limit(100)
      
    if (error) throw error

    // ONLY select jobs that have active photos stored in the CURRENT Supabase project
    // Batch size of 3 jobs ensures fast 5-8 second execution well within all timeouts
    const targetJobs = (allWithPhotos || []).filter(j => {
      const p = JSON.stringify(j.photo_urls || '') + JSON.stringify(j.after_photo_urls || '')
      return p.includes(`${currentProjectRef}.supabase.co`)
    }).slice(0, 3)

    console.log(`Found ${targetJobs.length} active jobs in current project ready to migrate.`)
    
    console.log(`Found ${targetJobs.length} completed reports ready for migration.`)
    let processedCount = 0;

    for (const job of targetJobs) {
      let photoUrls: string[] = []
      let afterPhotoUrls: string[] = []

      try {
        if (Array.isArray(job.photo_urls)) {
          photoUrls = job.photo_urls
        } else if (typeof job.photo_urls === 'string') {
          photoUrls = JSON.parse(job.photo_urls)
        }
      } catch (_) {
        photoUrls = []
      }

      try {
        if (Array.isArray(job.after_photo_urls)) {
          afterPhotoUrls = job.after_photo_urls
        } else if (typeof job.after_photo_urls === 'string') {
          afterPhotoUrls = JSON.parse(job.after_photo_urls)
        }
      } catch (_) {
        afterPhotoUrls = []
      }
      
      const allUrls = [...photoUrls, ...afterPhotoUrls]
      const supabaseUrls = allUrls.filter((url: string) => typeof url === 'string' && url.includes(`${currentProjectRef}.supabase.co`))
      
      if (supabaseUrls.length === 0) continue
      
      // Resolve Vehicle Number
      let vehicleNumber = job.job_card_id || `Job_${job.id}`
      if (job.vehicle_id) {
        const { data: vData } = await supabase
          .from('vehicles')
          .select('"Vehicle Number"')
          .eq('id', job.vehicle_id)
          .maybeSingle()
        if (vData && vData['Vehicle Number']) {
          vehicleNumber = vData['Vehicle Number']
        }
      }

      const clientPhone = job.client_phone || 'NoPhone'
      const folderName = `${vehicleNumber}_${clientPhone}`.replace(/[\/\\:*?"<>|]/g, '_')

      // 1. First, download all valid binaries before creating any Google Drive folder
      type PreparedPhoto = {
        originalUrl: string
        fileName: string
        rawBytes: Uint8Array
        mimeType: string
        bucketName: string
        filePath: string | null
      }

      const downloadBinary = async (url: string): Promise<PreparedPhoto | null> => {
        if (!url || typeof url !== 'string' || !url.includes('supabase.co/storage')) {
          return null
        }

        const bucketMatch = url.match(/\/storage\/v1\/object\/(?:public|authenticated|sign)\/([^\/]+)\/(.+)$/)
        const bucketName = bucketMatch ? bucketMatch[1] : 'job_photos'
        const filePath = bucketMatch ? decodeURIComponent(bucketMatch[2].split('?')[0]) : (url.split('/storage/v1/object/public/job_photos/')[1]?.split('?')[0] || null)
        const fileName = url.split('/').pop()?.split('?')[0] || `photo_${Date.now()}.jpg`

        let arrayBuffer: ArrayBuffer | null = null
        let mimeType = 'image/jpeg'

        // A. Download binary directly from Supabase Storage API
        if (filePath) {
          let { data: blob, error: dlErr } = await supabase.storage.from(bucketName).download(filePath)
          
          if (dlErr || !blob) {
            const strippedPath = filePath.replace(new RegExp(`^${bucketName}\/`), '')
            const retry = await supabase.storage.from(bucketName).download(strippedPath)
            if (!retry.error && retry.data) {
              blob = retry.data
              dlErr = null
            }
          }

          if (dlErr || !blob) {
            const addedPath = `${bucketName}/${filePath}`
            const retry2 = await supabase.storage.from(bucketName).download(addedPath)
            if (!retry2.error && retry2.data) {
              blob = retry2.data
              dlErr = null
            }
          }

          if (!dlErr && blob) {
            arrayBuffer = await blob.arrayBuffer()
            mimeType = blob.type || 'image/jpeg'
          }
        }

        // Fallback download via HTTP fetch
        if (!arrayBuffer || arrayBuffer.byteLength === 0) {
          try {
            const dlRes = await fetch(url, {
              headers: {
                'Authorization': `Bearer ${supabaseKey}`,
                'apikey': supabaseKey
              }
            })
            if (dlRes.ok) {
              arrayBuffer = await dlRes.arrayBuffer()
              mimeType = dlRes.headers.get('content-type') || 'image/jpeg'
            } else {
              console.error(`Fetch download failed (${dlRes.status}) for: ${url}`)
            }
          } catch (fetchErr) {
            console.error(`Fetch error for ${url}:`, fetchErr)
          }
        }

        if (!arrayBuffer || arrayBuffer.byteLength === 0) {
          return null
        }

        return {
          originalUrl: url,
          fileName,
          rawBytes: new Uint8Array(arrayBuffer),
          mimeType,
          bucketName,
          filePath
        }
      }

      // Download all photos for this job
      const [downloadedPhotoItems, downloadedAfterPhotoItems] = await Promise.all([
        Promise.all(photoUrls.map(url => downloadBinary(url))),
        Promise.all(afterPhotoUrls.map(url => downloadBinary(url)))
      ])

      const totalValidPhotos = downloadedPhotoItems.filter(Boolean).length + downloadedAfterPhotoItems.filter(Boolean).length

      if (totalValidPhotos === 0) {
        console.warn(`⚠️ Skipping job ${job.id}: All photo URLs are unreachable (dead/paused old project). Marking so cron moves forward.`)
        await supabase
          .from('reports')
          .update({ gdrive_folder_url: 'unreachable_storage' })
          .eq('id', job.id)
        continue
      }

      console.log(`Creating Drive folder: ${folderName} for report: ${job.id} (${totalValidPhotos} photos ready)`)

      // 2. Create subfolder in Google Drive only when photos are verified
      const folderRes = await fetch('https://www.googleapis.com/drive/v3/files?supportsAllDrives=true', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          name: folderName,
          mimeType: 'application/vnd.google-apps.folder',
          parents: [driveFolderId]
        })
      })
      
      const folderData = await folderRes.json()
      const newFolderId = folderData.id
      if (!newFolderId) {
        console.error('Folder creation failed for job', job.id, folderData)
        continue
      }
      
      // Grant public reader permission to folder
      try {
        await fetch(`https://www.googleapis.com/drive/v3/files/${newFolderId}/permissions?supportsAllDrives=true`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ role: 'reader', type: 'anyone' })
        })
      } catch (_) {}

      // 3. Upload downloaded photos to Google Drive
      const uploadPhoto = async (item: PreparedPhoto | null, fallbackUrl: string) => {
        if (!item) return fallbackUrl

        const boundary = '-------TYREX_BOUNDARY_31415926535'
        const metadata = JSON.stringify({
          name: item.fileName,
          parents: [newFolderId]
        })

        const head = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n--${boundary}\r\nContent-Type: ${item.mimeType}\r\n\r\n`
        const tail = `\r\n--${boundary}--`

        const encoder = new TextEncoder()
        const headBytes = encoder.encode(head)
        const tailBytes = encoder.encode(tail)

        const fullPayload = new Uint8Array(headBytes.byteLength + item.rawBytes.byteLength + tailBytes.byteLength)
        fullPayload.set(headBytes, 0)
        fullPayload.set(item.rawBytes, headBytes.byteLength)
        fullPayload.set(tailBytes, headBytes.byteLength + item.rawBytes.byteLength)

        const uploadRes = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id,size,webViewLink', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': `multipart/related; boundary=${boundary}`,
            'Content-Length': fullPayload.byteLength.toString()
          },
          body: fullPayload
        })

        const fileData = await uploadRes.json()
        const fileId = fileData.id

        if (!fileId) {
          console.error(`Upload failed for ${item.fileName}:`, fileData)
          return fallbackUrl
        }

        console.log(`✅ Uploaded intact: ${item.fileName} -> Drive ID: ${fileId} (${item.rawBytes.byteLength} bytes)`)

        // Set Public Reader Permission for File
        try {
          await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}/permissions?supportsAllDrives=true`, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${accessToken}`,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({ role: 'reader', type: 'anyone' })
          })
        } catch (_) {}
        
        // Delete from Supabase Storage only after verified Google Drive write
        if (item.filePath) {
           await supabase.storage.from(item.bucketName).remove([item.filePath])
        }
        
        return `https://lh3.googleusercontent.com/d/${fileId}#${item.fileName}`
      }

      const [updatedPhotoUrls, updatedAfterPhotoUrls] = await Promise.all([
        Promise.all(photoUrls.map((url, i) => uploadPhoto(downloadedPhotoItems[i], url))),
        Promise.all(afterPhotoUrls.map((url, i) => uploadPhoto(downloadedAfterPhotoItems[i], url)))
      ])
      
      // Update Database
      const { error: updateError } = await supabase
        .from('reports')
        .update({
          photo_urls: updatedPhotoUrls,
          after_photo_urls: updatedAfterPhotoUrls,
          gdrive_folder_url: `https://drive.google.com/drive/folders/${newFolderId}`
        })
        .eq('id', job.id)
        
      if (updateError) {
        console.error(`Failed to update DB for report ${job.id}:`, updateError)
      } else {
        console.log(`✅ Successfully migrated report ${job.id} to Google Drive (${folderName})`)
        processedCount++
      }
    }

    return new Response(JSON.stringify({ success: true, processed: processedCount }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error: any) {
    console.error('Edge Function Error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 400,
    })
  }
})
