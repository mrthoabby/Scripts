using ConferencesWebexScript.ApiTemplates;
using ConferencesWebexScript.Enums;
using ConferencesWebexScript.Helpers;
using System;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading.Tasks;

namespace ConferencesWebexScript.Services
{
    internal static class Conference
    {

        /// <summary>
        /// Crea una conferencia
        /// </summary>
        /// <param name="conferenceRequest"></param>
        /// <returns></returns>
        public static async Task<(bool IsConferenceCreate, ConferenceResponseCreate ConferenceContent)> CreateConferenceAsync(ConferenceRequestCreate conferenceRequest)
        {
            using (HttpClient _httpClient = new HttpClient())
            {
                conferenceRequest.Event = Enum.GetName(EnumEvents.start);
                try
                {
                    HttpResponseMessage response = await _httpClient.PostAsJsonAsync(ScriptConfigurationHelper._apiUrl, conferenceRequest);
                    return response.IsSuccessStatusCode ? (true, JsonSerializer.Deserialize<ConferenceResponseCreate>(await response.Content.ReadAsStringAsync())) : (false, null);

                }
                catch (Exception e)
                {
                    //Mepeando errores
                    throw new Exception(e.Message, e);
                }

            }
        }

        //Se espera poder actualizar una conferencia existente cuando la api permita hacerlo
        //public static async Task<bool> UpdateConference(string IdConference) => true;

        /// <summary>
        /// Este metodo se encarga de iniciar la grabación de la reunión bajo el id establecido en <seealso cref="_auToken"/>
        /// </summary>
        /// <param name="conferenceRequestRecording"></param>
        /// <returns></returns>
        /// <exception cref="Exception"></exception>
        public static async Task<(bool IsConferenceRecording, ConferenceResponseRecording ConferenceContent)> StartRecordingAsync(ConferenceRequestRecording conferenceRequestRecording)
        {
            using (HttpClient _httpClient = new HttpClient())
            {
                try
                {
                    HttpResponseMessage response = await _httpClient.PostAsJsonAsync(ScriptConfigurationHelper._apiUrl, conferenceRequestRecording);
                    return response.IsSuccessStatusCode ? (true, JsonSerializer.Deserialize<ConferenceResponseRecording>(await response.Content.ReadAsStringAsync())) : (false, null);

                }
                catch (Exception e)
                {
                    //Mepeando errores
                    throw new Exception(e.Message, e);
                }

            }
        }
    }
}
