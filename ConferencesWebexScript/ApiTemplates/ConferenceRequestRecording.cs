using ConferencesWebexScript.Entities;
using ConferencesWebexScript.Interfaces;

namespace ConferencesWebexScript.ApiTemplates
{
    internal class ConferenceRequestRecording : ICredentials
    {
        public string Event { get; set; }
        DataRecording Data_Recording { get; set; }
    }
}
