using ConferencesWebexScript.ApiTemplates;
using ConferencesWebexScript.Entities;
using ConferencesWebexScript.Enums;
using ConferencesWebexScript.Helpers;
using ConferencesWebexScript.Services;
using System;
using System.Threading.Tasks;

namespace ConferencesWebexScript
{
    internal class Program
    {
        private static async Task Main(string[] args)
        {

            //Se le adiciona 1 minuto a la tarea para que no se pisen las mangueras
            DateTime CurrentTime = DateTime.Now.AddMinutes(1);
            ConferenceRequestCreate _createConferenceTemplate = new ConferenceRequestCreate()
            {
                Event = Enum.GetName(EnumEvents.start),
                Data_create_update = ScriptConfigurationHelper.GetConferenceParameter(),
            };
            _createConferenceTemplate.Data_create_update.Start_time = CurrentTime.ToString("s");
            _createConferenceTemplate.Data_create_update.End_time = CurrentTime.AddHours(12).ToString("s");
            ConferenceRequestRecording _recordConeferenceTemplate = new ConferenceRequestRecording()
            {
                Event = Enum.GetName(EnumEvents.set_recording),
                Data_Recording = new DataRecording()
                {
                    meetingId = ScriptConfigurationHelper._meetingId,
                    recordingStarted = true,
                }
            };



            (bool IsConferenceRecording, ConferenceResponseRecording ConferenceContent) _conference = await Conference.StartRecordingAsync(_recordConeferenceTemplate);
            if (_conference.IsConferenceRecording)
            {
                ConferenceResponseRecording result = _conference.ConferenceContent;
                if(!string.IsNullOrEmpty(result.message)) Console.WriteLine( $"Error al intentar grabar sesión: {result.message}" );
            }

            Console.ReadKey();
        }



    }
}
